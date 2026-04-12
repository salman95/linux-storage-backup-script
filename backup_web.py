#!/usr/bin/env python3
"""
NAS Backup Web UI — Flask server
Provides a simple web interface to trigger and monitor backups via SSE.
"""

import json
import os
import subprocess
import threading
import time
from pathlib import Path
from flask import Flask, render_template, request, jsonify, Response

app = Flask(__name__)

# --- Configuration ---
SCRIPT_DIR = Path(__file__).resolve().parent
BACKUP_SCRIPT = SCRIPT_DIR / "Backups_web.sh"
SOURCE_DIRS = ["/mnt/Tech", "/mnt/Personal", "/mnt/Vids"]

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


def notify_subscribers():
    """Wake up all SSE subscriber threads."""
    with state_lock:
        for event in backup_state["subscribers"]:
            event.set()


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
            notify_subscribers()

        process.wait()

        with state_lock:
            if process.returncode != 0:
                backup_state["error"] = True
                backup_state["log"].append(
                    f"[ERROR] Script exited with code {process.returncode}"
                )
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
