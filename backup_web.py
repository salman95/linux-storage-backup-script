#!/usr/bin/env python3
"""
NAS Backup Web UI - Flask server
Provides a simple web interface to trigger and monitor backups via SSE.
"""

import json
import os
import subprocess
import threading
from pathlib import Path
from flask import Flask, render_template, request, jsonify, Response

app = Flask(__name__)
app.template_folder = str(Path(__file__).resolve().parent / "templates")

# --- Configuration ---
SCRIPT_DIR = Path(__file__).resolve().parent
BACKUP_SCRIPT = SCRIPT_DIR / "Backups_web.sh"
SOURCE_DIRS = ["/mnt/Tech", "/mnt/Personal", "/mnt/Vids"]
MAX_LOG_LINES = 2000  # cap in-memory log to prevent unbounded growth

# --- Update configuration ---
ANSIBLE_PLAYBOOK = SCRIPT_DIR / "ansible" / "playbook.yml"
UPDATE_HOSTS = [
    "archnas.lan",
    "radio.lan",
    "paperless-ngx.lan",
    "intel-ai.lan",
    "torrent.lan",
]

# --- State management ---
backup_lock = threading.Lock()
backup_state = {
    "running": False,
    "log": [],
    "progress_completed": 0,
    "progress_total": 0,
    "finished": False,
    "error": False,
    "subscribers": [],  # list of threading.Event for SSE clients
}
state_lock = threading.Lock()

# --- Update state management ---
update_lock = threading.Lock()
update_state = {
    "running": False,
    "log": [],
    "progress_completed": 0,
    "progress_total": 0,
    "finished": False,
    "error": False,
    "host_status": {},  # {"host.lan": {"status": "success|failed|pending", "task": ""}}
    "subscribers": [],
}


def notify_backup_subscribers():
    """Wake up all backup SSE subscriber threads."""
    with state_lock:
        for event in backup_state["subscribers"]:
            event.set()


def notify_update_subscribers():
    """Wake up all update SSE subscriber threads."""
    with state_lock:
        for event in update_state["subscribers"]:
            event.set()


def notify_subscribers():
    """Wake up all SSE subscriber threads (both backup and update)."""
    notify_backup_subscribers()
    notify_update_subscribers()


def run_backup(dirs: list[str]):
    """Execute the backup script in a subprocess and stream output."""
    try:
        with state_lock:
            backup_state["running"] = True
            backup_state["log"] = []
            backup_state["progress_completed"] = 0
            backup_state["progress_total"] = len(dirs)
            backup_state["finished"] = False
            backup_state["error"] = False

        notify_subscribers()

        cmd = ["bash", str(BACKUP_SCRIPT)] + dirs
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,  # line-buffered
        )

        for line in process.stdout:
            line = line.rstrip("\n")

            # Parse progress markers
            if line.startswith("PROGRESS:"):
                try:
                    parts = line.split(":")[1].split("/")
                    completed = int(parts[0])
                    total = int(parts[1])
                    with state_lock:
                        backup_state["progress_completed"] = completed
                        backup_state["progress_total"] = total
                except (IndexError, ValueError):
                    pass
                # Still log it for debugging, but don't show in UI
                with state_lock:
                    backup_state["log"].append(line)
                notify_subscribers()
                continue

            with state_lock:
                backup_state["log"].append(line)
                backup_state["log"] = backup_state["log"][-MAX_LOG_LINES:]
            notify_subscribers()

        process.wait()

        with state_lock:
            if process.returncode != 0:
                backup_state["error"] = True
                backup_state["log"].append(
                    f"[ERROR] Script exited with code {process.returncode}"
                )
                backup_state["log"] = backup_state["log"][-MAX_LOG_LINES:]
            backup_state["finished"] = True
            backup_state["running"] = False

        notify_subscribers()

    except Exception as e:
        with state_lock:
            backup_state["error"] = True
            backup_state["log"].append(f"[EXCEPTION] {str(e)}")
            backup_state["finished"] = True
            backup_state["running"] = False
        notify_subscribers()

    finally:
        backup_lock.release()


def run_updates():
    """Execute Ansible playbook in subprocess and stream output."""
    try:
        with state_lock:
            update_state["running"] = True
            update_state["log"] = []
            update_state["progress_completed"] = 0
            update_state["progress_total"] = len(UPDATE_HOSTS)
            update_state["finished"] = False
            update_state["error"] = False

        notify_update_subscribers()

        # Build ansible-playbook command
        cmd = [
            "ansible-playbook",
            "-i", str(SCRIPT_DIR / "ansible" / "inventory.yml"),
            str(ANSIBLE_PLAYBOOK),
        ]

        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = str(SCRIPT_DIR / "ansible" / "ansible.cfg")

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
        )

        # Track per-host status
        host_status = {host: {"status": "pending", "task": ""} for host in UPDATE_HOSTS}
        hosts_seen = set()
        for line in process.stdout:
            line = line.rstrip("\n")

            # Track per-host progress by parsing ok:/changed:/failed:/unreachable: lines
            for host in UPDATE_HOSTS:
                # Use word-boundary match to avoid false positives (e.g., "radio.lan" inside another path)
                if " " + host in line or line.startswith(host + " "):
                    if "failed:" in line or "unreachable:" in line:
                        host_status[host]["status"] = "failed"
                        host_status[host]["task"] = line[:50]
                    elif "changed:" in line:
                        host_status[host]["status"] = "success"
                        host_status[host]["task"] = line[:50]
                    elif "ok:" in line and "ok=" not in line:
                        # Exclude PLAY RECAP ok= lines
                        host_status[host]["status"] = "success"
                        host_status[host]["task"] = line[:50]
                    elif "skipping:" in line:
                        # Only mark as skipped if not already marked as success
                        if host_status[host]["status"] == "pending":
                            host_status[host]["status"] = "skipped"
                            host_status[host]["task"] = line[:50]

                    if any(
                        marker in line for marker in ["ok:", "changed:", "skipping:", "unreachable:", "failed:"]
                    ):
                        hosts_seen.add(host)

            with state_lock:
                update_state["log"].append(line)
                update_state["log"] = update_state["log"][-MAX_LOG_LINES:]
                update_state["progress_completed"] = len(hosts_seen)
                update_state["host_status"] = host_status.copy()

            notify_update_subscribers()

        process.wait()

        with state_lock:
            if process.returncode != 0:
                update_state["error"] = True
                update_state["log"].append(
                    f"[ERROR] Ansible exited with code {process.returncode}"
                )
                update_state["log"] = update_state["log"][-MAX_LOG_LINES:]
            update_state["finished"] = True
            update_state["running"] = False

        notify_update_subscribers()

    except Exception as e:
        with state_lock:
            update_state["error"] = True
            update_state["log"].append(f"[EXCEPTION] {str(e)}")
            update_state["finished"] = True
            update_state["running"] = False
        notify_update_subscribers()

    finally:
        update_lock.release()


@app.route("/")
def index():
    """Serve the main web UI."""
    return render_template("index.html", source_dirs=SOURCE_DIRS)


@app.route("/api/start", methods=["POST"])
def start_backup():
    """Start a backup with the selected directories."""
    data = request.get_json()
    selected = data.get("dirs", [])

    # Validate directories
    valid_dirs = [d for d in selected if d in SOURCE_DIRS]
    if not valid_dirs:
        return jsonify({"error": "No valid directories selected."}), 400

    # Try to acquire the lock (non-blocking)
    if not backup_lock.acquire(blocking=False):
        return jsonify({"error": "A backup is already running."}), 409

    # Start backup in a background thread
    thread = threading.Thread(target=run_backup, args=(valid_dirs,), daemon=True)
    thread.start()

    return jsonify({"status": "started", "dirs": valid_dirs})


@app.route("/api/update-systems", methods=["POST"])
def update_systems():
    """Start system updates via Ansible."""
    if not update_lock.acquire(blocking=False):
        return jsonify({"error": "An update is already running."}), 409
    thread = threading.Thread(target=run_updates, daemon=True)
    thread.start()
    return jsonify({"status": "started", "hosts": UPDATE_HOSTS})


@app.route("/api/update-status")
def update_status():
    """Return the current update state as JSON."""
    with state_lock:
        return jsonify({
            "running": update_state["running"],
            "finished": update_state["finished"],
            "error": update_state["error"],
            "progress_completed": update_state["progress_completed"],
            "progress_total": update_state["progress_total"],
            "log_length": len(update_state["log"]),
            "host_status": update_state["host_status"],
        })


@app.route("/api/update-stream")
def update_stream():
    """Server-Sent Events stream for real-time update logs."""
    def event_stream():
        my_event = threading.Event()
        with state_lock:
            update_state["subscribers"].append(my_event)

        last_sent_log_index = 0
        try:
            while True:
                my_event.wait(timeout=5)
                my_event.clear()

                with state_lock:
                    running = update_state["running"]
                    finished = update_state["finished"]
                    error = update_state["error"]
                    completed = update_state["progress_completed"]
                    total = update_state["progress_total"]
                    new_lines = update_state["log"][last_sent_log_index:]
                    host_status = update_state["host_status"].copy()
                    last_sent_log_index = len(update_state["log"])

                event_data = json.dumps({
                    "running": running,
                    "finished": finished,
                    "error": error,
                    "progress_completed": completed,
                    "progress_total": total,
                    "new_lines": new_lines,
                    "host_status": host_status,
                })
                yield f"data: {event_data}\n\n"

                if finished and not running:
                    break

        finally:
            with state_lock:
                if my_event in update_state["subscribers"]:
                    update_state["subscribers"].remove(my_event)

    return Response(
        event_stream(),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@app.route("/api/status")
def get_status():
    """Return the current backup state as JSON."""
    with state_lock:
        return jsonify({
            "running": backup_state["running"],
            "finished": backup_state["finished"],
            "error": backup_state["error"],
            "progress_completed": backup_state["progress_completed"],
            "progress_total": backup_state["progress_total"],
            "log_length": len(backup_state["log"]),
        })


@app.route("/api/stream")
def stream():
    """Server-Sent Events stream for real-time updates."""
    def event_stream():
        my_event = threading.Event()
        with state_lock:
            backup_state["subscribers"].append(my_event)

        last_sent_log_index = 0
        try:
            while True:
                # Wait for notification or timeout (for keepalive)
                my_event.wait(timeout=5)
                my_event.clear()

                with state_lock:
                    running = backup_state["running"]
                    finished = backup_state["finished"]
                    error = backup_state["error"]
                    completed = backup_state["progress_completed"]
                    total = backup_state["progress_total"]
                    new_lines = backup_state["log"][last_sent_log_index:]
                    last_sent_log_index = len(backup_state["log"])

                # Send progress update
                event_data = json.dumps({
                    "running": running,
                    "finished": finished,
                    "error": error,
                    "progress_completed": completed,
                    "progress_total": total,
                    "new_lines": new_lines,
                })
                yield f"data: {event_data}\n\n"

                # If backup finished, send one last update and close
                if finished and not running:
                    break

        finally:
            with state_lock:
                if my_event in backup_state["subscribers"]:
                    backup_state["subscribers"].remove(my_event)

    return Response(
        event_stream(),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
