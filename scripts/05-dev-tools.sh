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

echo "=== Development Tools Setup ==="
echo "Target user: $SUDO_USER"
echo "User home: $USER_HOME"
echo

# Git
install_git() {
    echo "[1/5] Installing Git..."

    if ! grep -q "^deb .*git-core/ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        add-apt-repository ppa:git-core/ppa -y
        apt-get update
    fi

    apt-get install -y git

    echo "Configuring Git for $SUDO_USER..."

    # Only set if not already configured
    if ! su - "$SUDO_USER" -c "git config --global core.editor" &>/dev/null; then
        su - "$SUDO_USER" -c "git config --global core.editor vim"
    fi

    if ! su - "$SUDO_USER" -c "git config --global init.defaultBranch" &>/dev/null; then
        su - "$SUDO_USER" -c "git config --global init.defaultBranch main"
    fi

    echo "Git version: $(git --version)"
    echo
    echo "REMINDER: Set your Git identity:"
    echo "  git config --global user.name \"Your Name\""
    echo "  git config --global user.email \"your.email@example.com\""
    echo
}

# Node.js via nvm
install_nodejs() {
    echo "[2/5] Installing Node.js via nvm..."

    local NVM_DIR="/home/$SUDO_USER/.nvm"
    local NVM_VERSION="v0.40.1"

    if [ -d "$NVM_DIR" ]; then
        echo "nvm already installed at $NVM_DIR"
    else
        echo "Installing nvm for $SUDO_USER..."
        su - "$SUDO_USER" -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash"
    fi

    # Install latest LTS Node.js
    echo "Installing Node.js LTS..."
    su - "$SUDO_USER" -c "
        export NVM_DIR='$NVM_DIR'
        [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
        nvm install --lts
        nvm use --lts
        nvm alias default 'lts/*'
    "

    # Verify installation
    local NODE_VERSION=$(su - "$SUDO_USER" -c "
        export NVM_DIR='$NVM_DIR'
        [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
        node --version
    ")

    echo "Node.js installed: $NODE_VERSION"
    echo "nvm directory: $NVM_DIR"
    echo
}

# Python
install_python() {
    echo "[3/5] Installing Python..."

    apt-get install -y python3 python3-pip python3-venv

    echo "Python version: $(python3 --version)"
    echo "pip version: $(pip3 --version)"
    echo
}

# VS Code
install_vscode() {
    echo "[4/5] Installing VS Code..."

    if ! command -v code &>/dev/null; then
        # Add Microsoft GPG key
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
        install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
        rm /tmp/packages.microsoft.gpg

        # Add VS Code repository
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list

        apt-get update
        apt-get install -y code
    else
        echo "VS Code already installed"
    fi

    echo "VS Code version: $(code --version | head -n1)"
    echo
}

# Additional tools
install_additional_tools() {
    echo "[5/5] Installing additional development tools..."

    apt-get install -y ripgrep fd-find bat shellcheck

    echo "Installed tools:"
    echo "  ripgrep: $(rg --version | head -n1)"
    echo "  fd: $(fdfind --version)"
    echo "  bat: $(bat --version)"
    echo "  shellcheck: $(shellcheck --version | grep version:)"
    echo
}

# Main execution
main() {
    install_git
    install_nodejs
    install_python
    install_vscode
    install_additional_tools

    echo "=== Development Tools Setup Complete ==="
    echo
    echo "Verification commands for $SUDO_USER:"
    echo "  git --version"
    echo "  node --version && npm --version"
    echo "  python3 --version"
    echo "  code --version"
    echo "  rg --version"
    echo
}

main
