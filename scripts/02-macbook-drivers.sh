#!/usr/bin/env bash
set -euo pipefail

# MacBook Pro 2013 specific drivers installation

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_warn() {
    echo "[WARN] $*"
}

install_broadcom_wifi() {
    log_info "Checking Broadcom WiFi driver..."

    if dpkg -l | grep -q "^ii.*bcmwl-kernel-source"; then
        log_info "bcmwl-kernel-source already installed"
        return 0
    fi

    if dpkg -l | grep -q "^ii.*broadcom-sta-dkms"; then
        log_info "broadcom-sta-dkms already installed"
        return 0
    fi

    # Ensure prerequisites for DKMS module build
    log_info "Installing kernel headers and DKMS prerequisites..."
    DEBIAN_FRONTEND=noninteractive apt install -y \
        linux-headers-$(uname -r) linux-headers-generic dkms || true

    # Fix any broken packages from previous attempts
    apt --fix-broken install -y 2>/dev/null || true

    log_info "Installing Broadcom WiFi driver (bcmwl-kernel-source)..."
    if DEBIAN_FRONTEND=noninteractive apt install -y bcmwl-kernel-source; then
        log_info "bcmwl-kernel-source installed successfully"
    else
        log_warn "bcmwl-kernel-source failed, trying broadcom-sta-dkms as fallback..."
        # Clean up broken state
        apt --fix-broken install -y 2>/dev/null || true
        dpkg --configure -a 2>/dev/null || true

        if DEBIAN_FRONTEND=noninteractive apt install -y broadcom-sta-dkms; then
            log_info "broadcom-sta-dkms installed successfully"
            # Blacklist conflicting modules and load wl
            echo "blacklist b43
blacklist bcma
blacklist ssb" > /etc/modprobe.d/broadcom-sta-blacklist.conf
            modprobe wl 2>/dev/null || true
        else
            log_error "Both WiFi drivers failed to install"
            apt --fix-broken install -y 2>/dev/null || true
            return 1
        fi
    fi
}

install_fan_control() {
    log_info "Checking fan control (mbpfan)..."

    if dpkg -l | grep -q "^ii.*mbpfan"; then
        log_info "mbpfan already installed"
    else
        log_info "Installing mbpfan..."
        if ! DEBIAN_FRONTEND=noninteractive apt install -y mbpfan; then
            log_error "Failed to install mbpfan"
            return 1
        fi
    fi

    log_info "Configuring mbpfan..."
    local config_file="/etc/mbpfan.conf"

    if [[ -f "$config_file" ]] && [[ ! -f "${config_file}.backup.orig" ]]; then
        cp "$config_file" "${config_file}.backup.orig"
    fi

    cat > "$config_file" << 'EOF'
[general]
min_fan_speed = 2000
max_fan_speed = 6200
low_temp = 55
high_temp = 65
max_temp = 86
polling_interval = 1
EOF

    systemctl enable mbpfan
    systemctl start mbpfan

    log_info "mbpfan installed and configured successfully"
}

install_backlight_keyboard() {
    log_info "Checking for pommed (backlight/keyboard control)..."

    if apt-cache show pommed &>/dev/null; then
        log_info "Installing pommed..."
        DEBIAN_FRONTEND=noninteractive apt install -y pommed || {
            log_warn "Failed to install pommed, but continuing..."
            return 1
        }
        log_info "pommed installed successfully"
    else
        log_warn "pommed not available in repositories (common for newer Ubuntu versions)"
        return 1
    fi
}

install_power_management() {
    log_info "Checking power management tools (thermald and tlp)..."

    local need_install=false
    if ! dpkg -l | grep -q "^ii.*thermald"; then
        need_install=true
    fi
    if ! dpkg -l | grep -q "^ii.*tlp "; then
        need_install=true
    fi

    if [[ "$need_install" == true ]]; then
        log_info "Installing thermald and tlp..."
        if ! DEBIAN_FRONTEND=noninteractive apt install -y thermald tlp; then
            log_error "Failed to install power management tools"
            return 1
        fi
    else
        log_info "thermald and tlp already installed"
    fi

    systemctl enable thermald
    systemctl start thermald || true

    systemctl enable tlp
    systemctl start tlp || true

    log_info "Power management tools installed and started successfully"
}

report_installation_status() {
    log_info "Driver installation summary:"

    local installed_count=0
    local total_count=4

    if dpkg -l | grep -q "^ii.*bcmwl-kernel-source"; then
        echo "  [OK] Broadcom WiFi driver (bcmwl-kernel-source)"
        ((installed_count++))
    elif dpkg -l | grep -q "^ii.*broadcom-sta-dkms"; then
        echo "  [OK] Broadcom WiFi driver (broadcom-sta-dkms)"
        ((installed_count++))
    else
        echo "  [FAIL] Broadcom WiFi driver"
    fi

    if systemctl is-enabled mbpfan &>/dev/null; then
        echo "  [OK] Fan control (mbpfan)"
        ((installed_count++))
    else
        echo "  [FAIL] Fan control (mbpfan)"
    fi

    if dpkg -l | grep -q pommed; then
        echo "  [OK] Backlight/keyboard control (pommed)"
        ((installed_count++))
    else
        echo "  [SKIP] Backlight/keyboard control (pommed not available)"
    fi

    if systemctl is-enabled thermald &>/dev/null && systemctl is-enabled tlp &>/dev/null; then
        echo "  [OK] Power management (thermald + tlp)"
        ((installed_count++))
    else
        echo "  [FAIL] Power management"
    fi

    log_info "Successfully installed: $installed_count/$total_count components"
}

main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    log_info "Starting MacBook Pro 2013 driver installation"

    apt update

    install_broadcom_wifi || true
    install_fan_control || true
    install_backlight_keyboard || true
    install_power_management || true

    report_installation_status

    log_info "MacBook Pro driver installation completed"
}

main "$@"
