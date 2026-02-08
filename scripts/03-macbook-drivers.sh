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

# Check for root
if [[ $EUID -ne 0 ]]; then
   err "This script must be run as root (use sudo)"
   exit 1
fi

CHANGES_MADE=()
ALREADY_CONFIGURED=()
REBOOT_RECOMMENDED=false

info "Starting MacBook hardware drivers installation..."

# Step 1: WiFi Driver (Broadcom BCM4360)
echo ""
info "════════════════════════════════════════════════════════════"
info "Configuring WiFi Driver (Broadcom BCM4360)"
info "════════════════════════════════════════════════════════════"

# 1a. Verify linux-headers
info "Verifying kernel headers..."
CURRENT_KERNEL=$(uname -r)
HEADERS_PKG="linux-headers-${CURRENT_KERNEL}"

if ! dpkg -l | grep -q "^ii.*${HEADERS_PKG}"; then
    warn "Kernel headers not found, installing..."
    DEBIAN_FRONTEND=noninteractive apt install -y "$HEADERS_PKG" linux-headers-generic || {
        err "Failed to install kernel headers"
        exit 1
    }
    CHANGES_MADE+=("Installed kernel headers for $CURRENT_KERNEL")
else
    ok "Kernel headers already installed"
fi

# 1b. Create blacklist file
info "Creating Broadcom driver blacklist..."
BLACKLIST_FILE="/etc/modprobe.d/blacklist-broadcom-wireless.conf"
BLACKLIST_CONTENT="# Blacklist conflicting Broadcom wireless drivers
blacklist b43
blacklist b43legacy
blacklist ssb
blacklist bcm43xx
blacklist brcm80211
blacklist brcmfmac
blacklist brcmsmac
blacklist bcma"

if [[ -f "$BLACKLIST_FILE" ]]; then
    # Check if content matches
    EXISTING_CONTENT=$(grep -v "^#" "$BLACKLIST_FILE" | grep -v "^$" | sort)
    EXPECTED_CONTENT=$(echo "$BLACKLIST_CONTENT" | grep -v "^#" | grep -v "^$" | sort)

    if [[ "$EXISTING_CONTENT" == "$EXPECTED_CONTENT" ]]; then
        ALREADY_CONFIGURED+=("Broadcom blacklist already correct")
        ok "Blacklist file already exists with correct content"
    else
        warn "Blacklist file exists but content differs, updating..."
        echo "$BLACKLIST_CONTENT" > "$BLACKLIST_FILE"
        CHANGES_MADE+=("Updated Broadcom blacklist file")
        REBOOT_RECOMMENDED=true
    fi
else
    info "Creating blacklist file..."
    echo "$BLACKLIST_CONTENT" > "$BLACKLIST_FILE"
    CHANGES_MADE+=("Created Broadcom blacklist file")
    REBOOT_RECOMMENDED=true
    ok "Blacklist file created"
fi

# 1c. Install broadcom-sta-dkms (PRIMARY driver)
info "Installing Broadcom WiFi driver (broadcom-sta-dkms)..."

if is_installed broadcom-sta-dkms; then
    ALREADY_CONFIGURED+=("broadcom-sta-dkms already installed")
    ok "Primary WiFi driver already installed"
else
    info "Installing broadcom-sta-dkms (primary driver for Ubuntu 24.04)..."

    # Try to install
    if DEBIAN_FRONTEND=noninteractive apt install -y broadcom-sta-dkms; then
        CHANGES_MADE+=("Installed broadcom-sta-dkms WiFi driver")
        ok "broadcom-sta-dkms installed successfully"
    else
        warn "broadcom-sta-dkms installation failed, attempting recovery..."

        # Try to fix broken packages
        dpkg --configure -a
        apt install -f -y

        # Try again
        if DEBIAN_FRONTEND=noninteractive apt install -y broadcom-sta-dkms; then
            CHANGES_MADE+=("Installed broadcom-sta-dkms after recovery")
            ok "broadcom-sta-dkms installed after recovery"
        else
            # 1d. Fallback to bcmwl-kernel-source
            warn "broadcom-sta-dkms failed, trying fallback driver (bcmwl-kernel-source)..."

            if DEBIAN_FRONTEND=noninteractive apt install -y bcmwl-kernel-source; then
                CHANGES_MADE+=("Installed bcmwl-kernel-source (fallback WiFi driver)")
                ok "Fallback WiFi driver installed"
            else
                err "Failed to install both WiFi drivers. Manual intervention required."
                err "Try: sudo apt install broadcom-sta-dkms bcmwl-kernel-source"
                exit 1
            fi
        fi
    fi
fi

# 1e. Update initramfs
info "Updating initramfs..."
update-initramfs -u -k all || {
    warn "initramfs update had warnings, continuing..."
}
ok "initramfs updated"

# 1f. Load the driver
info "Loading wl driver..."
if lsmod | grep -q "^wl "; then
    ALREADY_CONFIGURED+=("wl driver already loaded")
    ok "wl driver already loaded"
else
    if modprobe wl 2>/dev/null; then
        CHANGES_MADE+=("Loaded wl WiFi driver")
        ok "wl driver loaded successfully"
    else
        warn "Could not load wl driver (may require reboot)"
        REBOOT_RECOMMENDED=true
    fi
fi

# 1g. Verify
info "Verifying WiFi driver..."
if lsmod | grep -q wl; then
    ok "WiFi driver verification: wl module is loaded"
    lsmod | grep wl
else
    warn "wl module not loaded yet (reboot recommended)"
fi

# Step 2: Fan Control (mbpfan)
echo ""
info "════════════════════════════════════════════════════════════"
info "Installing Fan Control (mbpfan)"
info "════════════════════════════════════════════════════════════"

if is_installed mbpfan; then
    ALREADY_CONFIGURED+=("mbpfan already installed")

    # Check if service is active
    if systemctl is-active --quiet mbpfan; then
        ok "mbpfan already installed and running"
    else
        info "mbpfan installed but not running, starting service..."
        systemctl enable mbpfan
        systemctl start mbpfan
        CHANGES_MADE+=("Started mbpfan service")
        ok "mbpfan service started"
    fi
else
    info "Installing mbpfan..."
    DEBIAN_FRONTEND=noninteractive apt install -y mbpfan || {
        err "Failed to install mbpfan"
        exit 1
    }

    systemctl enable mbpfan
    systemctl start mbpfan
    CHANGES_MADE+=("Installed and started mbpfan")
    ok "mbpfan installed and running"
fi

# Verify mbpfan status
if systemctl is-active --quiet mbpfan; then
    ok "mbpfan service status: active"
else
    warn "mbpfan service is not active"
fi

# Step 3: Power Management (tlp)
echo ""
info "════════════════════════════════════════════════════════════"
info "Installing Power Management (tlp)"
info "════════════════════════════════════════════════════════════"

if is_installed tlp; then
    ALREADY_CONFIGURED+=("tlp already installed")

    # Check if service is active
    if systemctl is-active --quiet tlp; then
        ok "tlp already installed and running"
    else
        info "tlp installed but not running, starting service..."
        systemctl enable tlp
        systemctl start tlp
        CHANGES_MADE+=("Started tlp service")
        ok "tlp service started"
    fi
else
    info "Installing tlp..."
    DEBIAN_FRONTEND=noninteractive apt install -y tlp || {
        err "Failed to install tlp"
        exit 1
    }

    systemctl enable tlp
    systemctl start tlp
    CHANGES_MADE+=("Installed and started tlp")
    ok "tlp installed and running"
fi

# Verify tlp status
if systemctl is-active --quiet tlp; then
    ok "tlp service status: active"
else
    warn "tlp service is not active"
fi

# Step 4: Summary
echo ""
ok "═══════════════════════════════════════════════════════════"
ok "MacBook Drivers Installation Complete"
ok "═══════════════════════════════════════════════════════════"

if [[ ${#CHANGES_MADE[@]} -gt 0 ]]; then
    info "Changes made:"
    for change in "${CHANGES_MADE[@]}"; do
        echo "  ✓ $change"
    done
fi

if [[ ${#ALREADY_CONFIGURED[@]} -gt 0 ]]; then
    info "Already configured (skipped):"
    for item in "${ALREADY_CONFIGURED[@]}"; do
        echo "  • $item"
    done
fi

echo ""
info "Driver status:"
echo "  • WiFi (wl):    $(lsmod | grep -q wl && echo "✓ Loaded" || echo "⚠ Not loaded")"
echo "  • Fan (mbpfan): $(systemctl is-active --quiet mbpfan && echo "✓ Active" || echo "✗ Inactive")"
echo "  • Power (tlp):  $(systemctl is-active --quiet tlp && echo "✓ Active" || echo "✗ Inactive")"

if [[ "$REBOOT_RECOMMENDED" == true ]]; then
    warn "════════════════════════════════════════════════════════════"
    warn "REBOOT RECOMMENDED for WiFi and blacklist changes"
    warn "After reboot, check WiFi with: nmcli device status"
    warn "════════════════════════════════════════════════════════════"
else
    ok "No reboot required (all changes applied)"
fi

ok "═══════════════════════════════════════════════════════════"
