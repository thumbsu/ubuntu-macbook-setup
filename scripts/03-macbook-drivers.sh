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

# Patch broadcom-sta source for modern kernel compatibility
patch_broadcom_source() {
    # shellcheck disable=SC2086
    local bsta_dir makefile linuxver_h patched=false
    bsta_dir=$(echo /usr/src/broadcom-sta-*)
    if [[ ! -d "$bsta_dir" ]]; then
        warn "broadcom-sta source directory not found"
        return 1
    fi

    # Patch 1: Rename deprecated kbuild variables (kernel 6.12+)
    makefile="$bsta_dir/Makefile"
    if [[ -f "$makefile" ]] && grep -q "EXTRA_CFLAGS" "$makefile"; then
        info "Patching Makefile: EXTRA_CFLAGS -> ccflags-y (kernel 6.12+)"
        sed -i 's/EXTRA_CFLAGS/ccflags-y/g' "$makefile"
        patched=true
    fi
    if [[ -f "$makefile" ]] && grep -q "EXTRA_LDFLAGS" "$makefile"; then
        info "Patching Makefile: EXTRA_LDFLAGS -> ldflags-y (kernel 6.12+)"
        sed -i 's/EXTRA_LDFLAGS/ldflags-y/g' "$makefile"
        patched=true
    fi

    # Patch 2: Timer API compat (kernel 6.15+ removed from_timer/del_timer/del_timer_sync)
    linuxver_h="$bsta_dir/src/include/linuxver.h"
    if [[ -f "$linuxver_h" ]] && ! grep -q "timer_delete" "$linuxver_h"; then
        info "Patching linuxver.h: timer API compat (kernel 6.15+)"
        # Remove final #endif (header guard close), append compat block, re-add #endif
        sed -i '$ d' "$linuxver_h"
        {
            echo ''
            echo '/* Compat: kernel 6.15+ removed legacy timer APIs */'
            echo '#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)'
            echo '#define from_timer(var, callback_timer, timer_fieldname) \'
            echo '	timer_container_of(var, callback_timer, timer_fieldname)'
            echo '#define del_timer(t) timer_delete(t)'
            echo '#define del_timer_sync(t) timer_delete_sync(t)'
            echo '#endif'
            echo ''
            echo '#endif'
        } >> "$linuxver_h"
        patched=true
    fi

    # Patch 3: Disable -Werror for implicit-fallthrough (GCC treats WL_DBG macro
    # fallthrough as a warning; kernel build flags promote it to error)
    if [[ -f "$makefile" ]] && ! grep -q "Wno-error" "$makefile"; then
        info "Patching Makefile: disable -Werror=implicit-fallthrough"
        sed -i 's/^\(EXTRA_CFLAGS\|ccflags-y\) *:= *$/\1 := -Wno-error=implicit-fallthrough/' "$makefile"
        patched=true
    fi

    # Patch 4: cfg80211 API changes (kernel 6.17+ added radio_idx param to
    # set_wiphy_params, set_tx_power, and get_tx_power in struct cfg80211_ops)
    local cfg80211_file="$bsta_dir/src/wl/sys/wl_cfg80211_hybrid.c"
    if [[ -f "$cfg80211_file" ]] && ! grep -q "radio_idx" "$cfg80211_file"; then
        local kver_major kver_minor
        kver_major=$(uname -r | cut -d. -f1)
        kver_minor=$(uname -r | cut -d. -f2)
        if [[ "$kver_major" -ge 7 ]] || { [[ "$kver_major" -eq 6 ]] && [[ "$kver_minor" -ge 17 ]]; }; then
            info "Patching wl_cfg80211_hybrid.c: cfg80211 API (kernel 6.17+)"
            # get_tx_power: insert "int /*radio_idx*/," and add 6.17 #if guard
            perl -i -0777 -pe '
                s{(\#if LINUX_VERSION_CODE >= KERNEL_VERSION\(6, 14, 0\)\n)(static s32 wl_cfg80211_get_tx_power\(struct wiphy \*wiphy, struct wireless_dev \*wdev, )(u32 /\*link_id\*/, s32 \*dbm\))(;?)}{#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 17, 0)\n${2}int /*radio_idx*/, ${3}${4}\n#elif LINUX_VERSION_CODE >= KERNEL_VERSION(6, 14, 0)\n${2}${3}${4}}g;
            ' "$cfg80211_file"
            # set_tx_power: insert "int radio_idx," and add 6.17 #if guard
            perl -i -0777 -pe '
                s{(\#if LINUX_VERSION_CODE >= KERNEL_VERSION\(3, 8, 0\)\nstatic s32\nwl_cfg80211_set_tx_power\(struct wiphy \*wiphy, struct wireless_dev \*wdev,\n)(\s+)(enum nl80211_tx_power_setting type, s32 mbm\))(;?)}{#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 17, 0)\nstatic s32\nwl_cfg80211_set_tx_power(struct wiphy *wiphy, struct wireless_dev *wdev,\n${2}int radio_idx, ${3}${4}\n#elif LINUX_VERSION_CODE >= KERNEL_VERSION(3, 8, 0)\nstatic s32\nwl_cfg80211_set_tx_power(struct wiphy *wiphy, struct wireless_dev *wdev,\n${2}${3}${4}}g;
            ' "$cfg80211_file"
            # set_wiphy_params: insert "int radio_idx," and add 6.17 #if guard
            perl -i -0777 -pe '
                s{(static s32 wl_cfg80211_set_wiphy_params\(struct wiphy \*wiphy, )(u32 changed\))(;?)}{#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 17, 0)\n${1}int radio_idx, ${2}${3}\n#else\n${1}${2}${3}\n#endif}g;
            ' "$cfg80211_file"
            patched=true
        fi
    fi

    if [[ "$patched" == true ]]; then
        return 0
    fi
    return 1
}

# Purge broken broadcom packages so they don't poison apt operations
purge_broken_broadcom() {
    local pkg
    for pkg in bcmwl-kernel-source broadcom-sta-dkms; do
        if dpkg -l "$pkg" 2>/dev/null | grep -qE "^i[FHU]"; then
            warn "Purging broken $pkg..."
            dpkg --purge --force-remove-reinstreq "$pkg" 2>/dev/null || true
        fi
    done
    dkms remove broadcom-sta --all 2>/dev/null || true
}

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

# 1-pre. Purge broken broadcom packages BEFORE any apt operations
# A half-configured broadcom-sta-dkms poisons ALL apt commands
purge_broken_broadcom

# 1a. Verify linux-headers
info "Verifying kernel headers..."
CURRENT_KERNEL=$(uname -r)
HEADERS_PKG="linux-headers-${CURRENT_KERNEL}"

if ! is_installed "$HEADERS_PKG"; then
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

# 1c. Install broadcom-sta-dkms (PRIMARY driver for BCM4360)
info "Installing Broadcom WiFi driver (broadcom-sta-dkms)..."

WIFI_INSTALLED=false

# Already properly installed?
if is_installed broadcom-sta-dkms && dkms status broadcom-sta 2>/dev/null | grep -q "installed"; then
    ALREADY_CONFIGURED+=("broadcom-sta-dkms already installed")
    ok "Primary WiFi driver already installed and built"
    WIFI_INSTALLED=true
fi

if [[ "$WIFI_INSTALLED" == false ]]; then
    # Clean slate: purge any existing broadcom packages
    for pkg in bcmwl-kernel-source broadcom-sta-dkms; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^[ir]"; then
            dpkg --purge --force-remove-reinstreq "$pkg" 2>/dev/null || true
        fi
    done
    dkms remove broadcom-sta --all 2>/dev/null || true

    # Get the .deb file (from cache or download)
    DEB_FILE=$(find /var/cache/apt/archives/ -name "broadcom-sta-dkms_*.deb" -type f 2>/dev/null | head -1)
    if [[ -z "$DEB_FILE" ]]; then
        info "Downloading broadcom-sta-dkms..."
        DEBIAN_FRONTEND=noninteractive apt install -y --download-only broadcom-sta-dkms 2>/dev/null || true
        DEB_FILE=$(find /var/cache/apt/archives/ -name "broadcom-sta-dkms_*.deb" -type f 2>/dev/null | head -1)
    fi

    if [[ -n "$DEB_FILE" ]]; then
        # Step 1: Unpack ONLY (installs files, does NOT run post-inst / DKMS build)
        info "Unpacking broadcom-sta-dkms (without triggering DKMS build)..."
        dpkg --unpack "$DEB_FILE"

        # Step 2: Patch BEFORE DKMS build
        patch_broadcom_source || true

        # Step 3: Configure (post-inst triggers DKMS build with patched source)
        info "Configuring broadcom-sta-dkms (DKMS build with patched source)..."
        if dpkg --configure broadcom-sta-dkms; then
            CHANGES_MADE+=("Installed broadcom-sta-dkms with kernel compat patch")
            ok "broadcom-sta-dkms installed with kernel compatibility patch"
            WIFI_INSTALLED=true
        else
            err "broadcom-sta-dkms DKMS build failed after patching."
            info "Build log (last 20 lines):"
            # shellcheck disable=SC2086
            tail -20 /var/lib/dkms/broadcom-sta/*/build/make.log 2>/dev/null || true
            warn "Purging failed package..."
            dpkg --purge --force-remove-reinstreq broadcom-sta-dkms 2>/dev/null || true
        fi
    else
        err "Could not obtain broadcom-sta-dkms package."
    fi

    if [[ "$WIFI_INSTALLED" == false ]]; then
        err "WiFi driver installation failed. WiFi may not work."
        err "After reboot, try: sudo apt install broadcom-sta-dkms"
        REBOOT_RECOMMENDED=true
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
