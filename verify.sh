#!/usr/bin/env bash

# Verification script for Ubuntu 24.04 LTS MacBook Pro setup
# Run: ./verify.sh (no sudo needed for most checks)

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; ((WARN++)); }

echo "======================================"
echo " Ubuntu MacBook Setup Verification"
echo "======================================"
echo

# 01. System & Base Packages
echo "[01] System & Base Packages"
for pkg in curl wget git vim htop tmux net-tools unzip jq tree dkms; do
    if command -v "$pkg" &>/dev/null || dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        pass "$pkg"
    else
        fail "$pkg not found"
    fi
done

# Check linux-headers separately
if dpkg -l "linux-headers-$(uname -r)" 2>/dev/null | grep -q "^ii"; then
    pass "linux-headers-$(uname -r)"
else
    fail "linux-headers-$(uname -r) not found"
fi
echo

# 02. MacBook Drivers
echo "[02] MacBook Drivers"
if dpkg -l 2>/dev/null | grep -q "^ii.*bcmwl-kernel-source"; then
    pass "Broadcom WiFi driver (bcmwl-kernel-source)"
elif dpkg -l 2>/dev/null | grep -q "^ii.*broadcom-sta-dkms"; then
    pass "Broadcom WiFi driver (broadcom-sta-dkms)"
else
    fail "Broadcom WiFi driver not installed"
fi

if systemctl is-active --quiet mbpfan 2>/dev/null; then
    pass "mbpfan (fan control) running"
elif systemctl is-enabled --quiet mbpfan 2>/dev/null; then
    warn "mbpfan enabled but not running"
else
    fail "mbpfan not installed/enabled"
fi

if systemctl is-active --quiet thermald 2>/dev/null; then
    pass "thermald running"
else
    fail "thermald not running"
fi

if systemctl is-active --quiet tlp 2>/dev/null; then
    pass "tlp running"
elif systemctl is-enabled --quiet tlp 2>/dev/null; then
    pass "tlp enabled (runs on battery events)"
else
    fail "tlp not installed"
fi
echo

# 03. Korean Input
echo "[03] Korean Input (fcitx5)"
if dpkg -l 2>/dev/null | grep -q "fcitx5-hangul"; then
    pass "fcitx5-hangul installed"
else
    fail "fcitx5-hangul not installed"
fi

if grep -q "GTK_IM_MODULE=fcitx" /etc/environment 2>/dev/null; then
    pass "GTK_IM_MODULE set"
else
    fail "GTK_IM_MODULE not configured"
fi

if grep -q "QT_IM_MODULE=fcitx" /etc/environment 2>/dev/null; then
    pass "QT_IM_MODULE set"
else
    fail "QT_IM_MODULE not configured"
fi

if [ -f /etc/xdg/autostart/fcitx5.desktop ]; then
    pass "fcitx5 autostart entry"
else
    fail "fcitx5 autostart not configured"
fi
echo

# 04. Docker
echo "[04] Docker & Portainer"
if command -v docker &>/dev/null; then
    pass "Docker installed ($(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ','))"
else
    fail "Docker not installed"
fi

if docker info &>/dev/null 2>&1; then
    pass "Docker daemon running"
elif sudo docker info &>/dev/null 2>&1; then
    pass "Docker daemon running (needs sudo)"
else
    fail "Docker daemon not responding"
fi

if groups "${USER}" | grep -q '\bdocker\b'; then
    pass "User in docker group"
else
    warn "User not in docker group (need logout/login)"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^portainer$"; then
    pass "Portainer running"
elif sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^portainer$"; then
    pass "Portainer running"
else
    fail "Portainer not running"
fi
echo

# 05. Dev Tools
echo "[05] Development Tools"
if command -v git &>/dev/null; then
    pass "Git $(git --version | cut -d' ' -f3)"
else
    fail "Git not installed"
fi

NVM_DIR="$HOME/.nvm"
if [ -d "$NVM_DIR" ]; then
    pass "nvm installed"
    # Source nvm to check node
    export NVM_DIR
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    if command -v node &>/dev/null; then
        pass "Node.js $(node --version)"
    else
        warn "nvm installed but no Node.js version active"
    fi
else
    fail "nvm not installed"
fi

if command -v python3 &>/dev/null; then
    pass "Python $(python3 --version | cut -d' ' -f2)"
else
    fail "Python3 not installed"
fi

if command -v code &>/dev/null; then
    pass "VS Code installed"
else
    fail "VS Code not installed"
fi

if command -v rg &>/dev/null; then
    pass "ripgrep (rg)"
else
    fail "ripgrep not found"
fi

if command -v fdfind &>/dev/null || command -v fd &>/dev/null; then
    pass "fd-find"
else
    fail "fd-find not found"
fi

if command -v batcat &>/dev/null || command -v bat &>/dev/null; then
    pass "bat"
else
    fail "bat not found"
fi

if command -v shellcheck &>/dev/null; then
    pass "shellcheck"
else
    fail "shellcheck not found"
fi
echo

# 06. SSH
echo "[06] SSH Server"
if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    pass "SSH service running"
else
    fail "SSH service not running"
fi

if [ -f "$HOME/.ssh/id_ed25519" ]; then
    pass "SSH keypair exists"
else
    warn "No SSH keypair found"
fi

if grep -q "^PubkeyAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
    pass "Public key auth enabled"
else
    warn "PubkeyAuthentication not explicitly set"
fi

local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -n "$local_ip" ]; then
    pass "SSH accessible at: ${local_ip}:22"
fi
echo

# 07. Firewall
echo "[07] UFW Firewall"
if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    pass "UFW active"
    for port in "22/tcp" "80/tcp" "443/tcp" "9443/tcp"; do
        if sudo ufw status 2>/dev/null | grep -q "$port.*ALLOW"; then
            pass "Port $port allowed"
        else
            fail "Port $port not allowed"
        fi
    done
else
    fail "UFW not active"
fi
echo

# 08. System Tweaks
echo "[08] System Tweaks"
if grep -q "^HandleLidSwitch=ignore" /etc/systemd/logind.conf 2>/dev/null; then
    pass "Lid switch: ignore (won't sleep)"
else
    fail "Lid switch not configured"
fi

current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null)
if [ "$current_tz" = "Asia/Seoul" ]; then
    pass "Timezone: Asia/Seoul"
else
    fail "Timezone: $current_tz (expected Asia/Seoul)"
fi

if swapon --show 2>/dev/null | grep -q "/swapfile"; then
    swap_size=$(swapon --show 2>/dev/null | grep "/swapfile" | awk '{print $3}')
    pass "Swap active: $swap_size"
else
    fail "Swap not active"
fi

if ! systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
    pass "Auto-updates disabled"
else
    warn "Auto-updates still enabled"
fi

if grep -q "^WaylandEnable=false" /etc/gdm3/custom.conf 2>/dev/null; then
    pass "Wayland disabled (using X11)"
else
    warn "Wayland may still be enabled"
fi

session_type="${XDG_SESSION_TYPE:-unknown}"
if [ "$session_type" = "x11" ]; then
    pass "Current session: X11"
elif [ "$session_type" = "wayland" ]; then
    warn "Current session: Wayland (should be X11 after reboot)"
else
    warn "Session type: $session_type"
fi
echo

# 09. Keyboard Remap
echo "[09] Keyboard Remap (Toshy)"
TOSHY_DIR="$HOME/.local/share/toshy"
if [ -d "$TOSHY_DIR" ]; then
    pass "Toshy installed at $TOSHY_DIR"
else
    fail "Toshy not installed"
fi

if [ -f /etc/modprobe.d/hid_apple.conf ] && grep -q "fnmode=2" /etc/modprobe.d/hid_apple.conf 2>/dev/null; then
    pass "Fn key mode: F1-F12 default"
else
    fail "Fn key mode not configured"
fi
echo

# Summary
echo "======================================"
echo " Summary"
echo "======================================"
echo -e " ${GREEN}PASS${NC}: $PASS"
echo -e " ${RED}FAIL${NC}: $FAIL"
echo -e " ${YELLOW}WARN${NC}: $WARN"
echo

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
elif [ "$FAIL" -le 3 ]; then
    echo -e "${YELLOW}Mostly good, a few items need attention.${NC}"
else
    echo -e "${RED}Several checks failed. Re-run the setup or check logs.${NC}"
    echo "  Log: /var/log/ubuntu-setup.log"
    echo "  Re-run: sudo ./setup.sh"
fi
echo
