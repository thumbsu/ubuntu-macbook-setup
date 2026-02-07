#!/usr/bin/env bash

# Uninstall script for Ubuntu 24.04 LTS MacBook Pro setup
# Reverses changes made by setup.sh
#
# Usage:
#   sudo ./uninstall.sh              - Uninstall everything
#   sudo ./uninstall.sh --only NAME  - Uninstall specific component
#   ./uninstall.sh --list            - List components
#   ./uninstall.sh --dry-run         - Show what would be removed

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_done()  { echo -e "${GREEN}[DONE]${NC} $*"; }

run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} $*"
    else
        eval "$@"
    fi
}

COMPONENTS=(
    "09-keyboard-remap"
    "08-system-tweaks"
    "07-firewall"
    "06-ssh"
    "05-dev-tools"
    "04-docker"
    "03-korean-input"
    "02-macbook-drivers"
)
# Note: 01-system-update is NOT uninstalled (base packages are harmless)

uninstall_09() {
    log_info "Removing keyboard remap (Toshy + Fn key)..."

    local target_user="${SUDO_USER:-}"
    local user_home
    user_home=$(getent passwd "$target_user" | cut -d: -f6 2>/dev/null || echo "")

    # Remove Toshy
    if [[ -n "$user_home" ]] && [[ -d "$user_home/.local/share/toshy" ]]; then
        # Try Toshy's own uninstaller first
        if [[ -f "$user_home/.local/share/toshy/setup_toshy.py" ]]; then
            run "su - '$target_user' -c 'cd ~/.local/share/toshy && ./setup_toshy.py uninstall' || true"
        fi
        run "rm -rf '$user_home/.local/share/toshy'"
        log_done "Toshy removed"
    else
        log_info "Toshy not found, skipping"
    fi

    # Remove Fn key config
    if [[ -f /etc/modprobe.d/hid_apple.conf ]]; then
        run "rm -f /etc/modprobe.d/hid_apple.conf"
        run "update-initramfs -u 2>/dev/null || true"
        log_done "Fn key config removed"
    fi
}

uninstall_08() {
    log_info "Reverting system tweaks..."

    # Restore logind.conf
    local logind="/etc/systemd/logind.conf"
    if grep -q "^HandleLidSwitch=ignore" "$logind" 2>/dev/null; then
        run "sed -i 's/^HandleLidSwitch=ignore/#HandleLidSwitch=suspend/' '$logind'"
        run "sed -i 's/^HandleLidSwitchExternalPower=ignore/#HandleLidSwitchExternalPower=suspend/' '$logind'"
        log_done "Lid switch restored to default"
    fi

    # Re-enable auto-updates
    run "systemctl enable unattended-upgrades 2>/dev/null || true"
    run "systemctl enable apt-daily.timer 2>/dev/null || true"
    run "systemctl enable apt-daily-upgrade.timer 2>/dev/null || true"
    log_done "Auto-updates re-enabled"

    # Restore Wayland
    local gdm_conf="/etc/gdm3/custom.conf"
    if [[ -f "$gdm_conf" ]] && grep -q "^WaylandEnable=false" "$gdm_conf"; then
        run "sed -i 's/^WaylandEnable=false/#WaylandEnable=false/' '$gdm_conf'"
        log_done "Wayland re-enabled in GDM"
    fi

    # Note: swap and timezone are left as-is (harmless)
    log_info "Note: swap and timezone settings preserved"
}

uninstall_07() {
    log_info "Disabling UFW firewall..."

    if command -v ufw &>/dev/null; then
        run "ufw --force disable"
        run "ufw --force reset"
        log_done "UFW disabled and rules cleared"
    else
        log_info "UFW not installed, skipping"
    fi
}

uninstall_06() {
    log_info "Reverting SSH configuration..."

    # Restore original sshd_config if backup exists
    if [[ -f /etc/ssh/sshd_config.bak ]]; then
        run "cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config"
        run "systemctl restart ssh 2>/dev/null || true"
        log_done "SSH config restored from backup"
    else
        log_info "No sshd_config backup found, skipping"
    fi

    # Note: SSH server itself is not removed (useful to keep)
    log_info "Note: openssh-server kept installed"
}

uninstall_05() {
    log_info "Removing development tools..."

    local target_user="${SUDO_USER:-}"
    local user_home
    user_home=$(getent passwd "$target_user" | cut -d: -f6 2>/dev/null || echo "")

    # Remove VS Code
    if dpkg -l 2>/dev/null | grep -q "^ii.*code "; then
        run "apt remove -y code"
        run "rm -f /etc/apt/sources.list.d/vscode.list"
        run "rm -f /etc/apt/keyrings/packages.microsoft.gpg"
        log_done "VS Code removed"
    fi

    # Remove nvm + Node.js
    if [[ -n "$user_home" ]] && [[ -d "$user_home/.nvm" ]]; then
        run "rm -rf '$user_home/.nvm'"
        log_done "nvm + Node.js removed"
    fi

    # Remove additional tools
    run "apt remove -y ripgrep fd-find bat shellcheck 2>/dev/null || true"
    log_done "Additional tools removed"

    # Note: git, python3 are not removed (too fundamental)
    log_info "Note: git, python3 kept installed"
}

uninstall_04() {
    log_info "Removing Docker + Portainer..."

    # Stop Portainer
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local compose_file="${script_dir}/configs/docker-compose.yml"

    if [[ -f "$compose_file" ]] && command -v docker &>/dev/null; then
        run "docker compose -f '$compose_file' down -v 2>/dev/null || true"
        log_done "Portainer stopped and volume removed"
    fi

    # Remove Docker
    if dpkg -l 2>/dev/null | grep -q "docker-ce"; then
        run "apt remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true"
        run "apt autoremove -y"
        run "rm -f /etc/apt/sources.list.d/docker.list"
        run "rm -f /etc/apt/keyrings/docker.gpg"
        log_done "Docker removed"
    else
        log_info "Docker not installed, skipping"
    fi

    # Remove user from docker group
    local target_user="${SUDO_USER:-}"
    if [[ -n "$target_user" ]] && groups "$target_user" 2>/dev/null | grep -q '\bdocker\b'; then
        run "gpasswd -d '$target_user' docker 2>/dev/null || true"
        log_done "User removed from docker group"
    fi
}

uninstall_03() {
    log_info "Removing Korean input (fcitx5)..."

    run "apt remove -y fcitx5 fcitx5-hangul fcitx5-config-qt fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt5 2>/dev/null || true"
    run "apt autoremove -y"

    # Remove environment variables
    local env_file="/etc/environment"
    if [[ -f "$env_file" ]]; then
        run "sed -i '/^GTK_IM_MODULE=fcitx/d' '$env_file'"
        run "sed -i '/^QT_IM_MODULE=fcitx/d' '$env_file'"
        run "sed -i '/^XMODIFIERS=@im=fcitx/d' '$env_file'"
        run "sed -i '/^INPUT_METHOD=fcitx/d' '$env_file'"
        log_done "fcitx5 environment variables removed"
    fi

    # Remove autostart
    run "rm -f /etc/xdg/autostart/fcitx5.desktop"

    # Restore backup if exists
    if [[ -f "${env_file}.backup.pre-fcitx" ]]; then
        run "cp '${env_file}.backup.pre-fcitx' '$env_file'"
        log_done "Environment file restored from backup"
    fi

    log_done "Korean input removed"
}

uninstall_02() {
    log_info "Removing MacBook drivers..."

    # Remove WiFi driver
    if dpkg -l 2>/dev/null | grep -q "bcmwl-kernel-source"; then
        run "apt remove -y bcmwl-kernel-source"
        log_done "Broadcom WiFi driver removed"
    elif dpkg -l 2>/dev/null | grep -q "broadcom-sta-dkms"; then
        run "apt remove -y broadcom-sta-dkms"
        log_done "Broadcom STA driver removed"
    fi

    # Remove fan control
    if dpkg -l 2>/dev/null | grep -q "mbpfan"; then
        run "systemctl stop mbpfan 2>/dev/null || true"
        run "systemctl disable mbpfan 2>/dev/null || true"
        run "apt remove -y mbpfan"
        # Restore config backup
        if [[ -f /etc/mbpfan.conf.backup.orig ]]; then
            run "cp /etc/mbpfan.conf.backup.orig /etc/mbpfan.conf"
        fi
        log_done "mbpfan removed"
    fi

    # Remove power management
    run "apt remove -y thermald tlp 2>/dev/null || true"
    run "apt autoremove -y"

    log_done "MacBook drivers removed"
}

list_components() {
    echo "Components (uninstalled in reverse order):"
    echo ""
    echo "  09-keyboard-remap  Toshy + Fn key config"
    echo "  08-system-tweaks   Lid switch, timezone, Wayland, auto-updates"
    echo "  07-firewall        UFW rules"
    echo "  06-ssh             SSH config (server kept)"
    echo "  05-dev-tools       VS Code, nvm, ripgrep, etc. (git/python kept)"
    echo "  04-docker          Docker + Portainer"
    echo "  03-korean-input    fcitx5 + hangul"
    echo "  02-macbook-drivers Broadcom WiFi, mbpfan, thermald, tlp"
    echo ""
    echo "  Note: 01-system-update is NOT uninstalled (base packages are harmless)"
    echo ""
}

show_help() {
    cat << EOF
Usage: sudo $0 [OPTIONS]

Uninstall components installed by setup.sh.

OPTIONS:
    --help          Show this help
    --list          List removable components
    --only NAME     Remove only one component (e.g., --only docker)
    --dry-run       Show what would be removed without doing it

EXAMPLES:
    sudo $0                    # Remove everything
    sudo $0 --only docker      # Remove only Docker
    sudo $0 --dry-run          # Preview what would happen
EOF
}

find_component() {
    local query="$1"
    for comp in "${COMPONENTS[@]}"; do
        if [[ "$comp" == "$query" ]] || [[ "$comp" == *"$query"* ]]; then
            echo "$comp"
            return 0
        fi
    done
    return 1
}

main() {
    local only=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h) show_help; exit 0 ;;
            --list|-l) list_components; exit 0 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --only)
                [[ $# -lt 2 ]] && { log_error "--only requires a name"; exit 1; }
                only="$2"; shift 2 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done

    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" == false ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}=== DRY RUN MODE (no changes will be made) ===${NC}"
        echo
    fi

    if [[ -n "$only" ]]; then
        local comp
        if comp=$(find_component "$only"); then
            local num="${comp%%-*}"
            echo "Uninstalling: $comp"
            echo
            "uninstall_${num}"
        else
            log_error "Component not found: $only"
            list_components
            exit 1
        fi
    else
        echo "======================================"
        echo " Uninstalling ALL setup components"
        echo "======================================"
        echo

        for comp in "${COMPONENTS[@]}"; do
            local num="${comp%%-*}"
            echo "--- $comp ---"
            "uninstall_${num}"
            echo
        done
    fi

    if [[ "$DRY_RUN" == false ]]; then
        echo "======================================"
        echo " Uninstall complete"
        echo "======================================"
        echo
        echo "Recommended: sudo reboot"
    fi
}

main "$@"
