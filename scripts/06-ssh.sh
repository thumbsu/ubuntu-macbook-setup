#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

if [ -z "${SUDO_USER:-}" ]; then
    echo "ERROR: SUDO_USER not set. Run with sudo, not as root directly."
    exit 1
fi

USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
SSHD_CONFIG_SOURCE="$SCRIPT_DIR/../configs/sshd_config"

echo "=== SSH Server Setup ==="
echo "Target user: $SUDO_USER"
echo "User home: $USER_HOME"
echo

# Install SSH server
install_ssh_server() {
    echo "[1/6] Installing OpenSSH server..."

    apt-get install -y openssh-server

    echo "OpenSSH version: $(ssh -V 2>&1 | cut -d, -f1)"
    echo
}

# Backup and install sshd_config
configure_sshd() {
    echo "[2/6] Configuring SSH daemon..."

    if [ ! -f /etc/ssh/sshd_config.bak ]; then
        echo "Backing up original sshd_config..."
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    else
        echo "Backup already exists: /etc/ssh/sshd_config.bak"
    fi

    if [ ! -f "$SSHD_CONFIG_SOURCE" ]; then
        echo "ERROR: Custom sshd_config not found at $SSHD_CONFIG_SOURCE"
        exit 1
    fi

    echo "Installing custom sshd_config..."
    cp "$SSHD_CONFIG_SOURCE" /etc/ssh/sshd_config
    chmod 644 /etc/ssh/sshd_config

    echo "Custom sshd_config installed"
    echo
}

# Generate SSH host keys
generate_host_keys() {
    echo "[3/6] Generating SSH host keys..."

    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        ssh-keygen -A
        echo "SSH host keys generated"
    else
        echo "SSH host keys already exist"
    fi
    echo
}

# Setup user SSH directory
setup_user_ssh() {
    echo "[4/6] Setting up SSH directory for $SUDO_USER..."

    local SSH_DIR="$USER_HOME/.ssh"

    if [ ! -d "$SSH_DIR" ]; then
        mkdir -p "$SSH_DIR"
        chown "$SUDO_USER:$SUDO_USER" "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        echo "Created $SSH_DIR with proper permissions"
    else
        echo "$SSH_DIR already exists"
        chmod 700 "$SSH_DIR"
        chown "$SUDO_USER:$SUDO_USER" "$SSH_DIR"
    fi
    echo
}

# Generate user SSH keypair
generate_user_keypair() {
    echo "[5/6] Generating SSH keypair for $SUDO_USER..."

    local SSH_KEY="$USER_HOME/.ssh/id_ed25519"

    if [ ! -f "$SSH_KEY" ]; then
        echo "Generating ed25519 keypair..."
        su - "$SUDO_USER" -c "ssh-keygen -t ed25519 -C '$SUDO_USER@$(hostname)' -f '$SSH_KEY' -N ''"
        echo "Keypair generated: $SSH_KEY"
    else
        echo "Keypair already exists: $SSH_KEY"
    fi

    echo
    echo "=== PUBLIC KEY ==="
    cat "$SSH_KEY.pub"
    echo "=================="
    echo
    echo "To enable key-based authentication:"
    echo "1. Copy the above public key"
    echo "2. On your client machine, add it to ~/.ssh/authorized_keys on this server:"
    echo "   ssh-copy-id -i /path/to/your/key.pub $SUDO_USER@$(hostname -I | awk '{print $1}')"
    echo "   OR manually: echo 'PUBLIC_KEY' >> ~/.ssh/authorized_keys"
    echo
}

# Enable and restart SSH
enable_ssh_service() {
    echo "[6/6] Enabling and restarting SSH service..."

    systemctl enable ssh
    systemctl restart ssh

    echo "SSH service status: $(systemctl is-active ssh)"
    echo
}

# Print final instructions
print_instructions() {
    echo "=== SSH Server Setup Complete ==="
    echo
    echo "IMPORTANT: Password authentication is currently ENABLED for initial setup."
    echo
    echo "After adding your SSH keys, disable password authentication:"
    echo "  sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
    echo "  sudo systemctl restart sshd"
    echo
    echo "Current SSH configuration:"
    grep "^PasswordAuthentication" /etc/ssh/sshd_config || echo "  PasswordAuthentication (default: yes)"
    grep "^PubkeyAuthentication" /etc/ssh/sshd_config || echo "  PubkeyAuthentication (default: yes)"
    grep "^Port" /etc/ssh/sshd_config || echo "  Port (default: 22)"
    echo
}

# Main execution
main() {
    install_ssh_server
    configure_sshd
    generate_host_keys
    setup_user_ssh
    generate_user_keypair
    enable_ssh_service
    print_instructions
}

main
