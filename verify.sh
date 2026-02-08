#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# verify.sh - Installation verification for Ubuntu MacBook Pro Setup
# Run after setup.sh + reboot to check everything is working
# ============================================================

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓ PASS${NC}  $*"; ((PASS++)) || true; }
fail() { echo -e "  ${RED}✗ FAIL${NC}  $*"; ((FAIL++)) || true; }
skip() { echo -e "  ${YELLOW}~ WARN${NC}  $*"; ((WARN++)) || true; }

check_pkg() {
    if dpkg -l "$1" 2>/dev/null | grep -q "^ii"; then
        pass "$1 installed"
    else
        fail "$1 not installed"
    fi
}

check_service() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        pass "$1 service active"
    else
        fail "$1 service not active"
    fi
}

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║  Ubuntu MacBook Pro Setup - Verification ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# --- 01: System Update & Base Packages ---
echo -e "\n${BLUE}[01] System Update & Base Packages${NC}"
for pkg in curl wget git vim htop tmux net-tools build-essential unzip dkms; do
    check_pkg "$pkg"
done

# Kernel headers
KVER=$(uname -r)
if dpkg -l "linux-headers-${KVER}" 2>/dev/null | grep -q "^ii"; then
    pass "linux-headers-${KVER} installed"
else
    fail "linux-headers-${KVER} not installed"
fi

# --- 02: System Tweaks ---
echo -e "\n${BLUE}[02] System Tweaks${NC}"

# X11 / Wayland
if [[ -f /etc/gdm3/custom.conf ]]; then
    if grep -q "WaylandEnable=false" /etc/gdm3/custom.conf; then
        pass "Wayland disabled (X11 forced)"
    else
        fail "Wayland not disabled"
    fi
else
    skip "gdm3 custom.conf not found"
fi

# Check current session type
if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]]; then
    pass "Current session is X11"
elif [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    fail "Current session is Wayland (should be X11)"
else
    skip "Cannot determine session type (running from TTY?)"
fi

# Lid settings
if [[ -f /etc/systemd/logind.conf ]]; then
    if grep -q "HandleLidSwitch=ignore" /etc/systemd/logind.conf; then
        pass "Lid switch set to ignore"
    else
        fail "Lid switch not configured"
    fi
else
    fail "/etc/systemd/logind.conf not found"
fi

# Timezone
CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")
if [[ "$CURRENT_TZ" == "Asia/Seoul" ]]; then
    pass "Timezone: Asia/Seoul"
else
    fail "Timezone: $CURRENT_TZ (expected Asia/Seoul)"
fi

# Swap
if swapon --show 2>/dev/null | grep -q "/swapfile"; then
    SWAP_SIZE=$(swapon --show --noheadings --bytes 2>/dev/null | awk '{print $3}')
    pass "Swap active (/swapfile, $(numfmt --to=iec "$SWAP_SIZE" 2>/dev/null || echo "${SWAP_SIZE}B"))"
else
    skip "No swapfile found (may use partition swap)"
fi

# --- 03: MacBook Drivers ---
echo -e "\n${BLUE}[03] MacBook Drivers${NC}"

# WiFi blacklist
if [[ -f /etc/modprobe.d/blacklist-broadcom-wireless.conf ]]; then
    pass "Broadcom wireless blacklist exists"
else
    fail "Broadcom wireless blacklist missing"
fi

# WiFi driver module
if grep -q "^wl " /proc/modules 2>/dev/null; then
    pass "wl WiFi driver loaded"
else
    fail "wl WiFi driver not loaded"
fi

# WiFi connectivity
if command -v nmcli &>/dev/null; then
    WIFI_STATE=$(nmcli -t -f TYPE,STATE device 2>/dev/null | grep "^wifi:" | cut -d: -f2 || echo "unknown")
    if [[ "$WIFI_STATE" == "connected" ]]; then
        pass "WiFi connected"
    elif [[ "$WIFI_STATE" == "disconnected" ]]; then
        skip "WiFi available but not connected"
    else
        fail "WiFi state: $WIFI_STATE"
    fi
else
    skip "nmcli not available"
fi

# Fan control
check_service "mbpfan"

# Power management
check_service "tlp"

# --- 04: Claude Code ---
echo -e "\n${BLUE}[04] Claude Code${NC}"

# Claude Code may be installed for the regular user, not root
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~${REAL_USER}")
if [[ -x "${REAL_HOME}/.local/bin/claude" ]]; then
    CLAUDE_VER=$("${REAL_HOME}/.local/bin/claude" --version 2>/dev/null || echo "unknown")
    pass "Claude Code installed (${CLAUDE_VER})"
elif command -v claude &>/dev/null; then
    CLAUDE_VER=$(claude --version 2>/dev/null || echo "unknown")
    pass "Claude Code installed (${CLAUDE_VER})"
else
    skip "Claude Code not installed (optional)"
fi

# --- 05: Korean Input ---
echo -e "\n${BLUE}[05] Korean Input${NC}"

check_pkg "fcitx5"
check_pkg "fcitx5-hangul"

# Environment variables
if [[ -f /etc/environment ]]; then
    for var in GTK_IM_MODULE QT_IM_MODULE XMODIFIERS; do
        if grep -q "^${var}=" /etc/environment; then
            pass "${var} set in /etc/environment"
        else
            fail "${var} not set in /etc/environment"
        fi
    done
else
    fail "/etc/environment not found"
fi

# --- 06: Keyboard Remap ---
echo -e "\n${BLUE}[06] Keyboard Remap${NC}"

# Toshy
if [[ -d "${REAL_HOME}/toshy" ]]; then
    pass "Toshy installed (${REAL_HOME}/toshy)"
else
    skip "Toshy not installed (optional)"
fi

# Fn key
if [[ -f /etc/modprobe.d/hid_apple.conf ]]; then
    if grep -q "fnmode=2" /etc/modprobe.d/hid_apple.conf; then
        pass "Fn key mode set (fnmode=2)"
    else
        fail "Fn key mode not configured correctly"
    fi
else
    fail "hid_apple.conf not found"
fi

# --- 07: Docker ---
echo -e "\n${BLUE}[07] Docker${NC}"

if command -v docker &>/dev/null; then
    if docker info &>/dev/null; then
        pass "Docker Engine running"
        DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
        pass "Docker version: ${DOCKER_VER}"
    else
        fail "Docker installed but not running"
    fi
else
    fail "Docker not installed"
fi

# Docker Compose
if docker compose version &>/dev/null; then
    pass "Docker Compose available"
else
    fail "Docker Compose not available"
fi

# Portainer
if docker ps 2>/dev/null | grep -q portainer; then
    pass "Portainer running"
else
    fail "Portainer not running"
fi

# Docker group
if id "$REAL_USER" 2>/dev/null | grep -q "(docker)"; then
    pass "${REAL_USER} in docker group"
else
    fail "${REAL_USER} not in docker group"
fi

# --- 08: SSH & Firewall ---
echo -e "\n${BLUE}[08] SSH & Firewall${NC}"

# SSH
check_service "sshd"
if [[ -f /etc/ssh/sshd_config ]]; then
    if grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
        pass "Root login disabled"
    else
        fail "Root login not disabled"
    fi
    if grep -q "KbdInteractiveAuthentication no" /etc/ssh/sshd_config; then
        pass "KbdInteractiveAuthentication disabled"
    else
        skip "KbdInteractiveAuthentication not set"
    fi
    # Check for deprecated option
    if grep -q "ChallengeResponseAuthentication" /etc/ssh/sshd_config; then
        fail "Deprecated ChallengeResponseAuthentication found in sshd_config"
    else
        pass "No deprecated SSH options"
    fi
else
    fail "/etc/ssh/sshd_config not found"
fi

# UFW
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1 || echo "unknown")
    if echo "$UFW_STATUS" | grep -q "active"; then
        pass "UFW active"
    else
        fail "UFW not active"
    fi

    for rule in "22/tcp" "80/tcp" "443/tcp" "9443/tcp"; do
        if ufw status 2>/dev/null | grep -q "$rule"; then
            pass "UFW rule: ${rule} ALLOW"
        else
            fail "UFW rule missing: ${rule}"
        fi
    done
else
    fail "UFW not installed"
fi

# --- Forbidden patterns check ---
echo -e "\n${BLUE}[!!] Forbidden Pattern Check${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for forbidden patterns in all scripts
FORBIDDEN_FOUND=0
if grep -r "systemctl restart systemd-logind" "${SCRIPT_DIR}/scripts/" "${SCRIPT_DIR}/setup.sh" 2>/dev/null; then
    fail "FORBIDDEN: 'systemctl restart systemd-logind' found in scripts!"
    FORBIDDEN_FOUND=1
fi
if grep -r "ufw --force reset" "${SCRIPT_DIR}/scripts/" "${SCRIPT_DIR}/setup.sh" 2>/dev/null; then
    fail "FORBIDDEN: 'ufw --force reset' found in scripts!"
    FORBIDDEN_FOUND=1
fi
if grep -r "ChallengeResponseAuthentication" "${SCRIPT_DIR}/scripts/" "${SCRIPT_DIR}/setup.sh" "${SCRIPT_DIR}/configs/" 2>/dev/null; then
    fail "FORBIDDEN: 'ChallengeResponseAuthentication' found!"
    FORBIDDEN_FOUND=1
fi
if [[ $FORBIDDEN_FOUND -eq 0 ]]; then
    pass "No forbidden patterns found"
fi

# --- Summary ---
echo ""
echo -e "${BOLD}═══ Verification Summary ═══════════════════${NC}"
echo ""
echo -e "  ${GREEN}✓ PASS:${NC}  ${PASS}"
echo -e "  ${RED}✗ FAIL:${NC}  ${FAIL}"
echo -e "  ${YELLOW}~ WARN:${NC}  ${WARN}"
echo ""

echo "  Total: $((PASS + FAIL + WARN))"
echo ""
if [[ $FAIL -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}All checks passed!${NC}"
elif [[ $FAIL -le 3 ]]; then
    echo -e "  ${YELLOW}${BOLD}Mostly good, ${FAIL} issue(s) to review.${NC}"
else
    echo -e "  ${RED}${BOLD}${FAIL} issues found. Review failed checks above.${NC}"
fi
echo ""

exit $FAIL
