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

    if dpkg -l | grep -q bcmwl-kernel-source; then
        log_info "bcmwl-kernel-source already installed"
        return 0
    fi

    log_info "Installing Broadcom WiFi driver (bcmwl-kernel-source)..."
    DEBIAN_FRONTEND=noninteractive apt install -y bcmwl-kernel-source || {
        log_error "Failed to install bcmwl-kernel-source"
        return 1
    }
    log_info "Broadcom WiFi driver installed successfully"
}

install_fan_control() {
    log_info "Installing fan control (mbpfan)..."

    if ! DEBIAN_FRONTEND=noninteractive apt install -y mbpfan; then
        log_error "Failed to install mbpfan"
        return 1
    fi

    log_info "Configuring mbpfan..."
    local config_file="/etc/mbpfan.conf"

    if [[ -f "$config_file" ]]; then
        cp "$config_file" "${config_file}.backup"
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
    log_info "Installing power management tools (thermald and tlp)..."

    if ! DEBIAN_FRONTEND=noninteractive apt install -y thermald tlp; then
        log_error "Failed to install power management tools"
        return 1
    fi

    systemctl enable thermald
    systemctl start thermald

    systemctl enable tlp
    systemctl start tlp

    log_info "Power management tools installed and started successfully"
}

report_installation_status() {
    log_info "Driver installation summary:"

    local installed_count=0
    local total_count=4

    if dpkg -l | grep -q bcmwl-kernel-source; then
        echo "  [OK] Broadcom WiFi driver"
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
