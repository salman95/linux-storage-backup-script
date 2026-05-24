#!/bin/bash
set -euo pipefail

# --- Homelab Control Installation Script ---
# Installs dependencies, sets up systemd service, and configures Ansible

echo "========================================"
echo "Homelab Control Installation Script"
echo "========================================"
echo

# Detect package manager and determine sudo prefix
SUDO_CMD=""
if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo &>/dev/null; then
        echo "ERROR: sudo not found. Please install sudo or run as root."
        exit 1
    fi
    SUDO_CMD="sudo"
fi

if command -v pacman &>/dev/null; then
    PKG_INSTALL="$SUDO_CMD pacman -S --noconfirm"
elif command -v apt-get &>/dev/null; then
    PKG_INSTALL="$SUDO_CMD apt-get -y install"
else
    echo "ERROR: Unsupported package manager. Unable to proceed."
    exit 1
fi

echo "Detected package manager: ${PKG_INSTALL%% *}"
echo

# --- System Dependency Installation ---
echo "[1/6] Installing system dependencies..."
echo "  - Python 3 and pip"
echo "  - zstd (for compression)"
echo "  - ansible (and ansible-core)"
echo "  - sshpass (for password-based SSH)"
echo "  - pv (optional, for progress bar)"

# Get script directory for proper path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detect Python command (pip3 may not exist on Arch, use python3 -m pip)
if command -v pip3 &>/dev/null; then
    PIP_CMD="pip3"
elif command -v pip &>/dev/null; then
    PIP_CMD="pip"
else
    PIP_CMD="python3 -m pip"
fi

# Install Python 3 and pip
if ! command -v python3 &>/dev/null; then
    echo "Installing Python 3..."
    if [[ "$PKG_INSTALL" == *"pacman"* ]]; then
        $PKG_INSTALL python python-pip
    else
        $PKG_INSTALL python3 python3-pip
    fi
else
    echo "Python 3 already installed."
fi

# Install zstd
if ! command -v zstd &>/dev/null; then
    echo "Installing zstd..."
    $PKG_INSTALL zstd
else
    echo "zstd already installed."
fi

# Install ansible
if ! command -v ansible-playbook &>/dev/null; then
    echo "Installing ansible..."
    $PKG_INSTALL ansible
else
    echo "ansible already installed."
fi

# Install sshpass
if ! command -v sshpass &>/dev/null; then
    echo "Installing sshpass..."
    $PKG_INSTALL sshpass
else
    echo "sshpass already installed."
fi

# Install pv (optional)
if ! command -v pv &>/dev/null; then
    echo "Installing pv (for progress bar)..."
    $PKG_INSTALL pv
else
    echo "pv already installed (optional)."
fi

echo

# --- Python Dependencies ---
echo "[2/6] Installing Python dependencies..."
REQUIREMENTS_FILE="requirements.txt"
if [[ -f "$REQUIREMENTS_FILE" ]]; then
    echo "Installing with $PIP_CMD..."
    # Handle PEP 668 externally-managed-environment
    $PIP_CMD install --break-system-packages -r "$REQUIREMENTS_FILE"
    echo "Python dependencies installed."
else
    echo "WARNING: $REQUIREMENTS_FILE not found. Skipping."
fi
echo

# --- Ansible Configuration ---
echo "[3/6] Configuring Ansible..."

# Install community.general collection (required for pacman module)
echo "Installing community.general collection..."
ansible-galaxy collection install community.general --force || {
    echo "WARNING: Failed to install community.general collection."
    echo "         You may need to run manually: ansible-galaxy collection install community.general"
}

# Verify Ansible configuration files exist
ANSIBLE_DIR="ansible"
if [[ -d "$ANSIBLE_DIR" ]]; then
    echo "Ansible directory exists: $ANSIBLE_DIR"

    # Verify/create inventory.yml
    if [[ -f "$ANSIBLE_DIR/inventory.yml" ]]; then
        echo "  - inventory.yml: OK"
        # Verify YAML syntax
        if python3 -c "import yaml; yaml.safe_load(open('$ANSIBLE_DIR/inventory.yml'))" 2>/dev/null; then
            echo "  - inventory.yml syntax: VALID"
        else
            echo "  - inventory.yml syntax: INVALID - Fix YAML errors before running"
        fi
    else
        echo "  - inventory.yml: MISSING"
        if [[ -f "$ANSIBLE_DIR/inventory.yml.example" ]]; then
            echo "  Creating from template..."
            cp "$ANSIBLE_DIR/inventory.yml.example" "$ANSIBLE_DIR/inventory.yml"
            echo "  Created: $ANSIBLE_DIR/inventory.yml"
            echo
            echo "  ============================================"
            echo "  ACTION REQUIRED: Edit $ANSIBLE_DIR/inventory.yml"
            echo "  Replace YOUR_PASSWORD and YOUR_USER with real credentials."
            echo "  ============================================"
            echo
            # Ask if user wants to edit now
            read -r -p "  Open inventory.yml in your default editor now? [Y/n] " answer
            case "$answer" in
                n|N|no|No) echo "  Skipping. Edit it manually before running updates." ;;
                *)
                    EDITOR="${EDITOR:-nano}" $ANSIBLE_DIR/inventory.yml
                    echo "  Done editing. Remember: this file is in .gitignore (won't be committed)."
                    ;;
            esac
        fi
    fi

    # Verify playbook.yml
    if [[ -f "$ANSIBLE_DIR/playbook.yml" ]]; then
        echo "  - playbook.yml: OK"
    else
        echo "  - playbook.yml: MISSING"
    fi

    # Verify ansible.cfg
    if [[ -f "$ANSIBLE_DIR/ansible.cfg" ]]; then
        echo "  - ansible.cfg: OK"
    else
        echo "  - ansible.cfg: MISSING"
    fi
else
    echo "ERROR: Ansible directory '$ANSIBLE_DIR' not found."
    echo "       Run 'mkdir -p ansible' and create the required files."
    exit 1
fi
echo

# --- Service Setup ---
echo "[4/6] Setting up systemd service..."

SYSTEMD_DIR="/etc/systemd/system"
SERVICE_PATH="$SYSTEMD_DIR/backup-web.service"

# Skip systemd operations if not root
if [[ $EUID -ne 0 ]]; then
    echo "Note: Non-root detected. Service installation requires root."
    echo "      Run 'sudo ./install.sh' or manually:"
    echo "      sudo cp backup-web.service $SYSTEMD_DIR/"
    echo "      sudo systemctl daemon-reload"
    echo "      sudo systemctl enable backup-web.service"
    echo "      sudo systemctl start backup-web.service"
    SKIP_SERVICE=true
else
    SKIP_SERVICE=false
fi

if [[ "$SKIP_SERVICE" == "false" ]]; then
    SERVICE_USER="${SUDO_USER:-$USER}"

    # Generate systemd service from template with correct user and paths
    sed -e "s|{{USER}}|$SERVICE_USER|g" \
        -e "s|{{WORKING_DIR}}|$SCRIPT_DIR|g" \
        "$SCRIPT_DIR/backup-web.service.template" > "$SERVICE_PATH"

    echo "  - Created systemd service file: $SERVICE_PATH"

    # Reload systemd
    systemctl daemon-reload
    echo "  - Reloaded systemd daemon"

    # Enable service
    systemctl enable backup-web.service
    echo "  - Enabled backup-web.service"

    # Start service
    systemctl start backup-web.service
    echo "  - Started backup-web.service"

    echo
    echo "[5/6] Verifying service status..."
    systemctl status backup-web.service --no-pager || true
fi
echo

# --- Security Configuration ---
echo "[6/6] Security Configuration..."

# Check for password-based SSH in inventory
if [[ -f "$ANSIBLE_DIR/inventory.yml" ]]; then
    if grep -q "ansible_ssh_pass:" "$ANSIBLE_DIR/inventory.yml"; then
        echo "  WARNING: Password-based SSH detected in inventory!"
        echo "  Recommendation: Use Ansible Vault for credentials."
        echo "  Run: ansible-vault encrypt $ANSIBLE_DIR/inventory.yml"
        echo "  Then update service ExecStart to use: ansible-playbook --ask-vault-pass ..."
        echo
    fi
fi

# Check for sshpass availability
if ! command -v sshpass &>/dev/null; then
    echo "  WARNING: sshpass not found. Password-based SSH will fail."
    echo "  Install: sudo pacman -S sshpass  # or apt-get install sshpass"
    echo
fi

# --- Final Summary ---
echo "========================================"
echo "Installation Complete!"
echo "========================================"
echo
echo "Web interface: http://$(hostname -I | awk '{print $1}'):5000"
echo
echo "Quick Start:"
echo "  1. ansible/inventory.yml is created — fill in your real credentials"
echo "  2. Ensure password-based SSH works for all hosts:"
echo "     sshpass -p 'your_password' ssh root@hostname"
echo "  3. Restart service: sudo systemctl restart backup-web.service"
echo "  4. Access: http://$(hostname -I | awk '{print $1}'):5000"
echo
echo "Troubleshooting:"
echo "  - Check logs: journalctl -u backup-web.service -f"
echo "  - Manual test: python3 backup_web.py"
echo "  - Ansible test: ansible-playbook -i ansible/inventory.yml ansible/playbook.yml --check"
echo
