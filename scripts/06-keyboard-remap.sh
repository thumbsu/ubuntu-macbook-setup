#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

is_installed() { dpkg -l "$1" 2>/dev/null | grep -q "^ii"; }

# Determine what to run based on user context
IS_ROOT=false
if [[ $EUID -eq 0 ]]; then
    IS_ROOT=true
fi

# Part A: Toshy Installation (runs as regular user)
install_toshy() {
    info "Starting Toshy installation (macOS-like keyboard remapping)"

    TOSHY_DIR="$HOME/toshy"

    if [[ -d "$TOSHY_DIR" ]]; then
        ok "Toshy already installed at $TOSHY_DIR"
        return 0
    fi

    info "Installing Toshy using bootstrap script..."
    info "The installer may ask for sudo password when needed"

    # Download and run Toshy bootstrap script
    if bash -c "$(curl -fsSL https://raw.githubusercontent.com/RedBearAK/toshy/main/scripts/bootstrap.sh)"; then
        ok "Toshy bootstrap script completed"
    else
        warn "Toshy bootstrap script exited with non-zero status (this may be normal)"
    fi

    # Verify installation
    if [[ -d "$TOSHY_DIR" ]]; then
        ok "Toshy installed successfully at $TOSHY_DIR"
        info "Toshy services will start after reboot"
    else
        warn "Toshy directory not found after installation"
        warn "Manual installation may be required"
    fi
}

# Part B: Fn Key Mode Configuration (needs root)
configure_fn_key() {
    info "Configuring MacBook Fn key mode"

    MODPROBE_DIR="/etc/modprobe.d"
    HIDIAPPLE_CONF="$MODPROBE_DIR/hid_apple.conf"
    FNMODE_LINE="options hid_apple fnmode=2"

    # Create modprobe.d directory if it doesn't exist
    mkdir -p "$MODPROBE_DIR"

    # Check if already configured
    if [[ -f "$HIDIAPPLE_CONF" ]] && grep -q "^${FNMODE_LINE}$" "$HIDIAPPLE_CONF"; then
        ok "Fn key mode already configured (fnmode=2)"
    else
        info "Setting fnmode=2 (F1-F12 default, hold Fn for media keys)"

        # Backup existing file if it exists
        if [[ -f "$HIDIAPPLE_CONF" ]]; then
            cp "$HIDIAPPLE_CONF" "${HIDIAPPLE_CONF}.bak.$(date +%s)"
            warn "Backed up existing config"
        fi

        # Write configuration
        echo "$FNMODE_LINE" > "$HIDIAPPLE_CONF"
        ok "Created $HIDIAPPLE_CONF"

        # Update initramfs
        info "Updating initramfs..."
        update-initramfs -u
        ok "initramfs updated"

        info "Fn key configuration will take effect after reboot"
    fi
}

# Main execution logic
if $IS_ROOT; then
    # Running as root - do Fn key configuration only
    info "Running as root - configuring Fn key mode"
    configure_fn_key
    echo ""
    ok "Fn key configuration complete!"
    echo ""
else
    # Running as regular user - do Toshy installation only
    info "Running as regular user ($USER) - installing Toshy"
    install_toshy
    echo ""
    ok "Toshy installation complete!"
    echo ""
    info "Note: After reboot, Toshy will provide macOS-like keyboard shortcuts:"
    echo "  - Cmd+C/V/X (actually Super+C/V/X) for copy/paste/cut"
    echo "  - Cmd+Q to quit applications"
    echo "  - Cmd+W to close windows"
    echo "  - And many more macOS keyboard shortcuts"
    echo ""
fi

# Print summary
if $IS_ROOT; then
    info "Summary (Root tasks completed):"
    echo "  ✓ Fn key mode configured (fnmode=2)"
    echo "  ✓ initramfs updated"
    echo ""
    info "After reboot:"
    echo "  - F1-F12 will work as function keys by default"
    echo "  - Hold Fn for media controls (brightness, volume, etc.)"
else
    info "Summary (User tasks completed):"
    echo "  ✓ Toshy installation initiated"
    echo ""
    info "After reboot:"
    echo "  - Toshy services will start automatically"
    echo "  - macOS keyboard shortcuts will be active"
fi
