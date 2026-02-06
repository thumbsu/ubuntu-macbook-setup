#!/usr/bin/env bash
set -euo pipefail

# System update and base packages installation

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

update_system() {
    log_info "Updating package lists..."
    apt update

    log_info "Upgrading installed packages..."
    DEBIAN_FRONTEND=noninteractive apt upgrade -y
}

install_base_packages() {
    local packages=(
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
        apt-transport-https
        ca-certificates
        gnupg
        lsb-release
        tree
        jq
    )

    log_info "Installing base packages: ${packages[*]}"
    DEBIAN_FRONTEND=noninteractive apt install -y "${packages[@]}"
}

clean_apt_cache() {
    log_info "Cleaning apt cache..."
    apt autoremove -y
    apt clean
}

main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    log_info "Starting system update and base packages installation"

    update_system
    install_base_packages
    clean_apt_cache

    log_info "System update and base packages installation completed successfully"
}

main "$@"
