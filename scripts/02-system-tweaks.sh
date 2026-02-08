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
REBOOT_REQUIRED=false

info "Starting system tweaks configuration..."

# Step 1: Force X11 (disable Wayland)
info "Configuring X11 (disabling Wayland)..."
GDM_CONFIG="/etc/gdm3/custom.conf"

if [[ ! -f "$GDM_CONFIG" ]]; then
    if ! is_installed gdm3; then
        warn "GDM3 not installed, skipping Wayland disable"
    else
        warn "$GDM_CONFIG does not exist, skipping Wayland disable"
    fi
else
    # Check if WaylandEnable=false is already set
    if grep -q "^WaylandEnable=false" "$GDM_CONFIG"; then
        ALREADY_CONFIGURED+=("X11 already forced (Wayland disabled)")
    else
        # Check if [daemon] section exists
        if grep -q "^\[daemon\]" "$GDM_CONFIG"; then
            # Add WaylandEnable=false after [daemon] if not present
            if ! grep -A 5 "^\[daemon\]" "$GDM_CONFIG" | grep -q "WaylandEnable"; then
                sed -i '/^\[daemon\]/a WaylandEnable=false' "$GDM_CONFIG"
                CHANGES_MADE+=("Disabled Wayland in $GDM_CONFIG")
                REBOOT_REQUIRED=true
            else
                # WaylandEnable exists but might be set to true
                sed -i 's/^#*WaylandEnable=.*/WaylandEnable=false/' "$GDM_CONFIG"
                CHANGES_MADE+=("Set WaylandEnable=false in $GDM_CONFIG")
                REBOOT_REQUIRED=true
            fi
        else
            # Add [daemon] section with WaylandEnable=false
            echo -e "\n[daemon]\nWaylandEnable=false" >> "$GDM_CONFIG"
            CHANGES_MADE+=("Added [daemon] section and disabled Wayland in $GDM_CONFIG")
            REBOOT_REQUIRED=true
        fi
    fi
    ok "X11 configuration complete"
fi

# Step 2: Lid close settings (server mode)
info "Configuring lid close behavior (server mode)..."
LOGIND_CONFIG="/etc/systemd/logind.conf"

if [[ ! -f "$LOGIND_CONFIG" ]]; then
    warn "$LOGIND_CONFIG does not exist, creating it..."
    touch "$LOGIND_CONFIG"
fi

LID_SETTINGS=(
    "HandleLidSwitch=ignore"
    "HandleLidSwitchExternalPower=ignore"
    "HandleLidSwitchDocked=ignore"
)

LID_CHANGES=0
for setting in "${LID_SETTINGS[@]}"; do
    key="${setting%%=*}"
    value="${setting#*=}"

    # Check if setting is already correct (uncommented)
    if grep -q "^${key}=${value}" "$LOGIND_CONFIG"; then
        continue
    fi

    # Check if commented version exists
    if grep -q "^#${key}=" "$LOGIND_CONFIG"; then
        # Replace commented line
        sed -i "s/^#${key}=.*/${setting}/" "$LOGIND_CONFIG"
        ((LID_CHANGES++))
    elif grep -q "^${key}=" "$LOGIND_CONFIG"; then
        # Replace existing uncommented line with different value
        sed -i "s/^${key}=.*/${setting}/" "$LOGIND_CONFIG"
        ((LID_CHANGES++))
    else
        # Add new line
        echo "$setting" >> "$LOGIND_CONFIG"
        ((LID_CHANGES++))
    fi
done

if [[ $LID_CHANGES -gt 0 ]]; then
    CHANGES_MADE+=("Configured lid close behavior to ignore (server mode)")
    REBOOT_REQUIRED=true
    ok "Lid close settings configured (DO NOT restart systemd-logind - reboot required)"
else
    ALREADY_CONFIGURED+=("Lid close already configured to ignore")
    ok "Lid close settings already correct"
fi

# Step 3: Timezone
info "Configuring timezone..."
CURRENT_TZ=$(timedatectl show -p Timezone --value)
TARGET_TZ="Asia/Seoul"

if [[ "$CURRENT_TZ" == "$TARGET_TZ" ]]; then
    ALREADY_CONFIGURED+=("Timezone already set to $TARGET_TZ")
    ok "Timezone already correct"
else
    timedatectl set-timezone "$TARGET_TZ" || {
        err "Failed to set timezone"
        exit 1
    }
    CHANGES_MADE+=("Set timezone to $TARGET_TZ (was: $CURRENT_TZ)")
    ok "Timezone set to $TARGET_TZ"
fi

# Step 4: Swap
info "Configuring swap..."
SWAPFILE="/swapfile"
SWAP_SIZE="4G"

# Check if swap is already active
if swapon --show | grep -q "$SWAPFILE"; then
    ALREADY_CONFIGURED+=("Swap already active at $SWAPFILE")
    ok "Swap already configured"
elif [[ -f "$SWAPFILE" ]]; then
    # Swapfile exists but not active, activate it
    warn "Swapfile exists but not active, activating..."
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE"
    swapon "$SWAPFILE"

    # Add to fstab if not present
    if ! grep -q "$SWAPFILE" /etc/fstab; then
        echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
        CHANGES_MADE+=("Activated existing swapfile and added to /etc/fstab")
    else
        CHANGES_MADE+=("Activated existing swapfile")
    fi
    ok "Swapfile activated"
else
    # Create new swapfile
    info "Creating $SWAP_SIZE swapfile..."
    fallocate -l "$SWAP_SIZE" "$SWAPFILE" || dd if=/dev/zero of="$SWAPFILE" bs=1M count=4096
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE"
    swapon "$SWAPFILE"

    # Add to fstab
    if ! grep -q "$SWAPFILE" /etc/fstab; then
        echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
    fi

    CHANGES_MADE+=("Created and activated $SWAP_SIZE swapfile")
    ok "Swapfile created and activated"
fi

# Step 5: Disable unattended-upgrades
info "Disabling unattended-upgrades (server stability)..."
UNATTENDED_DISABLED=0

# Check if service is active
if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
    systemctl disable --now unattended-upgrades
    CHANGES_MADE+=("Disabled unattended-upgrades service")
    ((UNATTENDED_DISABLED++))
fi

# Check if package is installed
if is_installed unattended-upgrades; then
    DEBIAN_FRONTEND=noninteractive apt remove -y unattended-upgrades
    CHANGES_MADE+=("Removed unattended-upgrades package")
    ((UNATTENDED_DISABLED++))
fi

if [[ $UNATTENDED_DISABLED -eq 0 ]]; then
    ALREADY_CONFIGURED+=("Unattended-upgrades already disabled/removed")
    ok "Unattended-upgrades already disabled"
else
    ok "Unattended-upgrades disabled and removed"
fi

# Step 6: Summary
echo ""
ok "═══════════════════════════════════════════════════════════"
ok "System Tweaks Complete"
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

if [[ "$REBOOT_REQUIRED" == true ]]; then
    warn "════════════════════════════════════════════════════════════"
    warn "REBOOT REQUIRED for X11 and lid settings to take effect"
    warn "════════════════════════════════════════════════════════════"
else
    ok "No reboot required"
fi

ok "═══════════════════════════════════════════════════════════"
