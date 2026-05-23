# Homelab Control

A web-based control panel for homelab management with **NAS backup** and **system updates** capabilities. Features a dark-themed UI with real-time progress tracking via Server-Sent Events (SSE).

## Features

### Backup System
- **Compress & archive** — Multi-threaded zstd compression (`.tar.zst`)
- **Directory selection** — Choose source directories via checkboxes
- **Real-time progress** — Live progress bar with per-directory completion
- **Live log streaming** — Color-coded log output via SSE
- **Concurrent prevention** — Single backup execution at a time
- **Retention policy** — Keeps last 3 backup directories
- **Integrity verification** — Archive validation after creation

### System Updates (via Ansible)
- **Update all containers & VMs** — One-click Ansible automation
- **Per-host status grid** — Visual feedback on each host's update status
- **OS detection** — Automatically selects pacman (Arch) or apt (Debian)
- **Live progress** — Tracks hosts completed vs total
- **Concurrent prevention** — Single update operation at a time

---

## Project Structure

```
├── Backups.sh                 # Original CLI backup script
├── Backups_web.sh             # Web-friendly version (accepts dirs as args)
├── backup_web.py              # Flask web server
├── templates/
│   └── index.html             # Web UI (dark theme, progress bars, host status grid)
├── ansible/
│   ├── ansible.cfg            # Ansible config (disable host key checking)
│   ├── inventory.yml          # Host inventory with SSH credentials
│   └── playbook.yml           # System update playbook (OS-aware)
├── backup-web.service         # Systemd service file
├── requirements.txt           # Python dependencies
├── install.sh                 # Automated installation script
└── README.md
```

---

## Prerequisites

### For Arch Linux
```bash
sudo pacman -S python python-pip zstd ansible sshpass pv
```

### For Debian/Ubuntu
```bash
sudo apt-get install python3 python3-pip zstd ansible sshpass pv
```

Then install Python dependencies:
```bash
pip3 install -r requirements.txt
```

### Ansible Collections
```bash
ansible-galaxy collection install community.general
```

---

## Automated Installation

Run the installation script (requires root):
```bash
sudo ./install.sh
```

This will:
1. Install all system dependencies (Python, zstd, ansible, sshpass, pv)
2. Install Python dependencies (Flask)
3. Install `community.general` Ansible collection
4. Validate Ansible configuration files
5. Create and enable systemd service
6. Start the web server

---

## Deployment

### Manual Installation
```bash
cd /home/youruser
git clone https://github.com/salman95/linux-storage-backup-script.git
cd linux-storage-backup-script

# Install dependencies
pip3 install -r requirements.txt
ansible-galaxy collection install community.general

# Configure inventory with your hosts (see Configuration section)
# Edit ansible/inventory.yml

# Start the web server
python3 backup_web.py
```

### Systemd Service (auto-start on boot)
```bash
# The install.sh script handles this automatically
# Or manually:
sudo cp backup-web.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable backup-web.service
sudo systemctl start backup-web.service
```

---

## Configuration

### Ansible Inventory (SSH Credentials)
Edit `ansible/inventory.yml` with your hosts:

```yaml
all:
  hosts:
    archnas.lan:
      ansible_port: 2222
      ansible_user: salman95
      ansible_ssh_pass: your_password
      ansible_become_pass: your_password
    radio.lan:
      ansible_user: root
      ansible_ssh_pass: your_password
    # ... add more hosts
```

**Security Note:** Passwords are stored in plaintext. For production, use:
```bash
ansible-vault encrypt ansible/inventory.yml
```

### Web Server
Edit `backup_web.py`:

| Setting | Default |
|---|---|
| `SOURCE_DIRS` | `["/mnt/Tech", "/mnt/Personal", "/mnt/Vids"]` |
| `app.run(port=)` | `5000` |

### Backup Script
Edit `Backups_web.sh`:

| Setting | Default |
|---|---|
| `backup_root` | `/mnt/Backups` |
| `KEEP` | `3` (retention count) |
| `MIN_FREE_KB` | `2 GB` |

---

## Usage

### Access the Web UI
Open in any browser on your network:
```
http://your-server-ip:5000
```

### Trigger Backup
1. Select source directories via checkboxes
2. Click **▶ Start Backup**

### Trigger System Updates
1. Click **⚡ Update All Containers & VMs**
2. Monitor progress via the status grid and log output

### Check Service Status
```bash
systemctl status backup-web.service
journalctl -u backup-web.service -f
```

---

## CLI Usage (Original Backup Script)

```bash
./Backups.sh
```

Edit `crontab` for scheduled backups:
```bash
sudo crontab -e
```

---

## Password Locations

All SSH passwords are stored in **one location**:
- **`ansible/inventory.yml`** — Plaintext SSH credentials for all hosts

**No passwords are stored elsewhere.** This file contains:
- `ansible_ssh_pass` — SSH connection password
- `ansible_become_pass` — Sudo/privilege escalation password (for non-root users)

---

## Security Notes

- **No authentication** — Designed for LAN-only access. Use a VPN (e.g., WireGuard) for remote access.
- **Password-based SSH** — Requires `sshpass`. Consider using Ansible Vault for production.
- **No root required** — Runs as a non-root user (configure in `backup-web.service`).

---

## Troubleshooting

### Ansible Connection Errors
```bash
# Test SSH connectivity manually
sshpass -p 'your_password' ssh user@hostname

# Test Ansible playbook (dry run)
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml --check
```

### Web UI Not Starting
```bash
# Check service status
systemctl status backup-web.service
journalctl -u backup-web.service -f

# Run manually to see errors
python3 backup_web.py
```

### Python Dependencies
```bash
# Check Flask is installed
pip3 show flask

# Reinstall if needed
pip3 install --break-system-packages -r requirements.txt
```

### Host Key Verification
If you see SSH host key errors:
- The `ansible.cfg` disables host key checking by default
- Or manually accept host keys first: `ssh user@hostname`

---

## License

Same as original: MIT
