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

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

echo "=== Keyboard Remapping Setup ==="
echo "Target user: $SUDO_USER"
echo "User home: $USER_HOME"
echo

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_packages=()

    if ! command -v git &>/dev/null; then
        missing_packages+=("git")
    fi

    if ! command -v python3 &>/dev/null; then
        missing_packages+=("python3")
    fi

    if ! command -v pip3 &>/dev/null; then
        missing_packages+=("python3-pip")
    fi

    if [ ${#missing_packages[@]} -gt 0 ]; then
        log_error "Missing required packages: ${missing_packages[*]}"
        log_error "Please run 05-dev-tools.sh first"
        exit 1
    fi

    log_info "All prerequisites satisfied"
    echo
}

# Install Toshy
install_toshy() {
    log_info "Installing Toshy..."

    local TOSHY_DIR="$USER_HOME/.local/share/toshy"

    if [ -d "$TOSHY_DIR" ]; then
        log_info "Toshy already installed at $TOSHY_DIR"
        echo
        return 0
    fi

    log_info "Cloning Toshy repository..."
    su - "$SUDO_USER" -c "
        mkdir -p '$USER_HOME/.local/share'
        git clone https://github.com/RedBearAK/toshy.git '$TOSHY_DIR'
    "

    log_info "Running Toshy installer..."
    cd "$TOSHY_DIR"
    su - "$SUDO_USER" -c "cd '$TOSHY_DIR' && ./setup_toshy.py install"

    log_info "Toshy installation complete"
    echo
}

# Configure MacBook Fn key
configure_fn_key() {
    log_info "Configuring MacBook Fn key..."

    local MODPROBE_CONF="/etc/modprobe.d/hid_apple.conf"
    local FN_MODE_CONFIG="options hid_apple fnmode=2"

    if [ -f "$MODPROBE_CONF" ] && grep -q "^options hid_apple fnmode=2" "$MODPROBE_CONF"; then
        log_info "Fn key already configured in $MODPROBE_CONF"
        echo
        return 0
    fi

    log_info "Writing Fn key configuration to $MODPROBE_CONF..."
    echo "$FN_MODE_CONFIG" > "$MODPROBE_CONF"

    log_info "Updating initramfs..."
    update-initramfs -u

    log_info "Fn key configuration complete"
    echo
}

# Main execution
main() {
    check_prerequisites
    install_toshy
    configure_fn_key

    echo "=== Keyboard Remapping Setup Complete ==="
    echo
    echo "IMPORTANT: Reboot required for Fn key changes to take effect"
    echo
    echo "Next steps:"
    echo "  1. Reboot your system"
    echo "  2. For Wayland (GNOME): Enable Toshy extension in GNOME Extensions"
    echo "  3. Check status: toshy-config-start"
    echo "  4. Toggle Toshy: Ctrl+Space"
    echo
    echo "Fn key mode: Function keys work as F1-F12 by default"
    echo "             Hold Fn for media keys (brightness, volume, etc.)"
    echo
}

main
