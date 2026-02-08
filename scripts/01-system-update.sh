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

info "Starting system update and base package installation..."

# Step 1: System update
info "Updating package lists..."
apt update || { err "apt update failed"; exit 1; }

info "Upgrading installed packages..."
DEBIAN_FRONTEND=noninteractive apt upgrade -y || { err "apt upgrade failed"; exit 1; }
ok "System updated"

# Step 2: Install base packages
BASE_PACKAGES=(
    curl
    wget
    git
    vim
    htop
    tmux
    net-tools
    build-essential
    unzip
    software-properties-common
    bat         # This is the package name for batcat on Ubuntu
    fd-find     # This is the package name for fdfind on Ubuntu
)

info "Checking base packages..."
TO_INSTALL=()
ALREADY_INSTALLED=()

for pkg in "${BASE_PACKAGES[@]}"; do
    if is_installed "$pkg"; then
        ALREADY_INSTALLED+=("$pkg")
    else
        TO_INSTALL+=("$pkg")
    fi
done

if [[ ${#ALREADY_INSTALLED[@]} -gt 0 ]]; then
    ok "Already installed: ${ALREADY_INSTALLED[*]}"
fi

if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    info "Installing: ${TO_INSTALL[*]}"
    DEBIAN_FRONTEND=noninteractive apt install -y "${TO_INSTALL[@]}" || {
        err "Failed to install base packages"
        exit 1
    }
    ok "Installed: ${TO_INSTALL[*]}"
else
    ok "All base packages already installed"
fi

# Step 3: Install kernel headers and DKMS (CRITICAL for WiFi driver)
info "Checking kernel headers and DKMS..."
KERNEL_PACKAGES=(
    linux-headers-generic
    "linux-headers-$(uname -r)"
    dkms
)

KERNEL_TO_INSTALL=()
KERNEL_ALREADY_INSTALLED=()

for pkg in "${KERNEL_PACKAGES[@]}"; do
    # Handle the dynamic kernel version package specially
    if [[ "$pkg" == linux-headers-* ]]; then
        # Check if any version of this package is installed
        if dpkg -l | grep -q "^ii.*${pkg}"; then
            KERNEL_ALREADY_INSTALLED+=("$pkg")
        else
            KERNEL_TO_INSTALL+=("$pkg")
        fi
    elif is_installed "$pkg"; then
        KERNEL_ALREADY_INSTALLED+=("$pkg")
    else
        KERNEL_TO_INSTALL+=("$pkg")
    fi
done

if [[ ${#KERNEL_ALREADY_INSTALLED[@]} -gt 0 ]]; then
    ok "Already installed: ${KERNEL_ALREADY_INSTALLED[*]}"
fi

if [[ ${#KERNEL_TO_INSTALL[@]} -gt 0 ]]; then
    info "Installing kernel headers and DKMS: ${KERNEL_TO_INSTALL[*]}"
    DEBIAN_FRONTEND=noninteractive apt install -y "${KERNEL_TO_INSTALL[@]}" || {
        err "Failed to install kernel headers/DKMS"
        exit 1
    }
    ok "Installed: ${KERNEL_TO_INSTALL[*]}"
else
    ok "All kernel headers and DKMS already installed"
fi

# Step 4: Summary
echo ""
ok "═══════════════════════════════════════════════════════════"
ok "System Update Complete"
ok "═══════════════════════════════════════════════════════════"
if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    info "Newly installed base packages: ${TO_INSTALL[*]}"
fi
if [[ ${#KERNEL_TO_INSTALL[@]} -gt 0 ]]; then
    info "Newly installed kernel packages: ${KERNEL_TO_INSTALL[*]}"
fi
if [[ ${#ALREADY_INSTALLED[@]} -gt 0 ]] || [[ ${#KERNEL_ALREADY_INSTALLED[@]} -gt 0 ]]; then
    info "Already configured packages were skipped"
fi
ok "Kernel version: $(uname -r)"
ok "Ready for WiFi driver installation in next step"
ok "═══════════════════════════════════════════════════════════"
