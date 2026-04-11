# linux-storage-backup-script

A simple script that will compress and backup all your drives content into one location, now with a **web-based UI** for easy triggering and monitoring.

The idea is to move the contents of one or multiple drives into another designated backup location. The content will be placed in an archive file (`.tar.zst`) with the source directory name, using multi-threaded zstd compression.

You can also run the original script as a cronjob, or use the web UI to trigger backups on demand.

![2023-07-19_16-17](https://github.com/salman95/linux-storage-backup-script/assets/25572063/a8230db6-d4c7-483b-a0e8-aba6a2d1485b)

---

## Features

- **Web Dashboard** — Dark-themed UI accessible on your local network
- **Directory selection** — Choose which source directories to back up via checkboxes
- **Real-time progress** — Progress bar tracks per-directory completion
- **Live log streaming** — Color-coded log output via Server-Sent Events (SSE)
- **Concurrent backup prevention** — Only one backup can run at a time
- **Retention policy** — Automatically keeps only the last 3 backup directories
- **Integrity verification** — Each archive is tested after creation

---

## Project Structure

```
├── Backups.sh            # Original CLI backup script
├── Backups_web.sh        # Web-friendly version (accepts dirs as args, no interactive prompts)
├── backup_web.py         # Flask web server
├── templates/
│   └── index.html        # Web UI (dark theme, progress bar, log view)
├── backup-web.service    # Systemd service file
├── requirements.txt      # Python dependencies
└── README.md
```

---

## Prerequisites

On the NAS server (Arch Linux), install the following:

```bash
# Python 3 and pip
sudo pacman -S python python-pip

# zstd for compression (pzstd preferred for parallel compression)
sudo pacman -S zstd

# Flask
pip install -r requirements.txt
```

---

## Deployment on NAS Server

### 1. Clone the repository

```bash
cd /home/salman95
git clone https://github.com/salman95/linux-storage-backup-script.git
cd linux-storage-backup-script
```

### 2. Install Python dependencies

```bash
pip install -r requirements.txt
```

### 3. Make the backup script executable

```bash
chmod +x Backups_web.sh
```

### 4. Test manually

```bash
python3 backup_web.py
```

Then open `http://192.168.2.6:5000` in your browser.

### 5. Set up as a systemd service (auto-start on boot)

```bash
# Copy the service file
sudo cp backup-web.service /etc/systemd/system/

# Reload systemd, enable, and start
sudo systemctl daemon-reload
sudo systemctl enable backup-web.service
sudo systemctl start backup-web.service

# Check status
sudo systemctl status backup-web.service
```

### 6. Access the Web UI

Open in any browser on your network:

```
http://192.168.2.6:5000
```

---

## Configuration

Edit these values in the respective files:

| Setting | File | Default |
|---|---|---|
| Source directories | `backup_web.py` → `SOURCE_DIRS` | `/mnt/Tech`, `/mnt/Personal`, `/mnt/Vids` |
| Backup destination | `Backups_web.sh` → `backup_root` | `/mnt/Backups` |
| Retention count | `Backups_web.sh` → `KEEP` | `3` |
| Min free space | `Backups_web.sh` → `MIN_FREE_KB` | `2 GB` |
| Web server port | `backup_web.py` → `app.run(port=)` | `5000` |

---

## CLI Usage (Original Script)

The original `Backups.sh` script still works standalone:

```bash
./Backups.sh
```

Edit `crontab` for scheduled backups: `sudo crontab -e`

---

## Notes

- **No authentication** — This is designed for LAN-only access. Use a VPN (e.g., WireGuard) for remote access.
- **No root required** — Runs as `salman95` as long as the user has read access to source dirs and write access to the backup destination.
- The systemd service assumes the repo is cloned to `/home/salman95/linux-storage-backup-script`. Adjust the paths in `backup-web.service` if you clone it elsewhere.
