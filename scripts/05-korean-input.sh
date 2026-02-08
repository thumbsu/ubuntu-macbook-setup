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

if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)"
    exit 1
fi

info "Starting Korean input setup (fcitx5 + Hangul)"

# Step 1: Install fcitx5 packages
PACKAGES=(fcitx5 fcitx5-hangul fcitx5-config-qt im-config)
NEED_INSTALL=false

for pkg in "${PACKAGES[@]}"; do
    if is_installed "$pkg"; then
        ok "$pkg already installed"
    else
        info "Will install $pkg"
        NEED_INSTALL=true
    fi
done

if $NEED_INSTALL; then
    info "Installing fcitx5 packages..."
    apt-get update -qq
    apt-get install -y "${PACKAGES[@]}"
    ok "fcitx5 packages installed"
else
    ok "All fcitx5 packages already installed"
fi

# Step 2: Set environment variables in /etc/environment
ENV_FILE="/etc/environment"
ENV_VARS=(
    "GTK_IM_MODULE=fcitx"
    "QT_IM_MODULE=fcitx"
    "XMODIFIERS=@im=fcitx"
)

info "Configuring environment variables in $ENV_FILE"
MODIFIED=false

for var in "${ENV_VARS[@]}"; do
    if grep -q "^${var}$" "$ENV_FILE" 2>/dev/null; then
        ok "$var already set"
    else
        echo "$var" >> "$ENV_FILE"
        ok "Added $var"
        MODIFIED=true
    fi
done

if $MODIFIED; then
    ok "Environment variables updated"
else
    ok "Environment variables already configured"
fi

# Step 3: Set fcitx5 as default input method
info "Setting fcitx5 as default input method"
if command -v im-config >/dev/null 2>&1; then
    im-config -n fcitx5
    ok "fcitx5 set as default input method"
else
    warn "im-config command not found, skipping"
fi

# Step 4: Disable GNOME's built-in Super+Space keybinding
if [[ -n "${SUDO_USER:-}" ]]; then
    info "Disabling GNOME Super+Space keybinding for user: $SUDO_USER"

    # Run as the actual user (not root)
    if su - "$SUDO_USER" -c "gsettings set org.gnome.desktop.wm.keybindings switch-input-source \"['']\"" 2>/dev/null; then
        ok "Disabled switch-input-source keybinding"
    else
        warn "Could not set switch-input-source keybinding (may not be in GNOME session)"
    fi

    if su - "$SUDO_USER" -c "gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward \"['']\"" 2>/dev/null; then
        ok "Disabled switch-input-source-backward keybinding"
    else
        warn "Could not set switch-input-source-backward keybinding (may not be in GNOME session)"
    fi
else
    warn "SUDO_USER not set, cannot disable GNOME keybindings"
    warn "You may need to manually disable Super+Space in GNOME Settings"
fi

# Print guidance
echo ""
ok "Korean input setup complete!"
echo ""
info "Next steps:"
echo "  1. Reboot your system: sudo reboot"
echo "  2. After reboot, open fcitx5-configtool"
echo "  3. In Global Options → Trigger Input Method → set to Super+Space (Cmd+Space)"
echo "  4. Add Hangul input method if not already present"
echo "  5. Test by pressing Super+Space in any text field"
echo ""
