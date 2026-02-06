#!/usr/bin/env bash
set -euo pipefail

# Korean input method setup (fcitx5 + hangul)

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

install_fcitx5() {
    log_info "Installing fcitx5 and Korean input components..."

    if dpkg -l | grep -q "^ii.*fcitx5-hangul"; then
        log_info "fcitx5-hangul already installed, skipping"
        return 0
    fi

    local packages=(
        fcitx5
        fcitx5-hangul
        fcitx5-config-qt
        fcitx5-frontend-gtk3
        fcitx5-frontend-gtk4
        fcitx5-frontend-qt5
    )

    DEBIAN_FRONTEND=noninteractive apt install -y "${packages[@]}"

    log_info "fcitx5 packages installed successfully"
}

configure_environment_variables() {
    log_info "Configuring environment variables in /etc/environment..."

    local env_file="/etc/environment"
    local env_vars=(
        "GTK_IM_MODULE=fcitx"
        "QT_IM_MODULE=fcitx"
        "XMODIFIERS=@im=fcitx"
        "INPUT_METHOD=fcitx"
    )

    if [[ -f "$env_file" ]] && [[ ! -f "${env_file}.backup.pre-fcitx" ]]; then
        cp "$env_file" "${env_file}.backup.pre-fcitx"
    fi

    for var in "${env_vars[@]}"; do
        local key="${var%%=*}"
        if grep -q "^${key}=" "$env_file" 2>/dev/null; then
            log_info "Updating existing $key in $env_file"
            sed -i "s|^${key}=.*|${var}|" "$env_file"
        else
            log_info "Adding $key to $env_file"
            echo "$var" >> "$env_file"
        fi
    done

    log_info "Environment variables configured successfully"
}

create_autostart_entry() {
    log_info "Creating fcitx5 autostart entry..."

    local autostart_dir="/etc/xdg/autostart"
    local desktop_file="${autostart_dir}/fcitx5.desktop"

    mkdir -p "$autostart_dir"

    cat > "$desktop_file" << 'EOF'
[Desktop Entry]
Type=Application
Name=Fcitx 5
GenericName=Input Method
Comment=Start Fcitx 5 Input Method Framework
Exec=fcitx5
Icon=fcitx
Terminal=false
Categories=System;Utility;
StartupNotify=false
X-GNOME-Autostart-Phase=Applications
X-GNOME-AutoRestart=true
X-GNOME-Autostart-Notify=false
X-KDE-autostart-phase=1
EOF

    log_info "Autostart entry created at $desktop_file"
}

print_completion_note() {
    cat << 'EOF'

==========================================================
Korean input (fcitx5) installation completed successfully
==========================================================

NEXT STEPS:
1. Log out and log back in (or reboot)
2. Open fcitx5 settings (search for "Fcitx Configuration")
3. Click "+" to add input method
4. Search for "Hangul" and add it
5. Set a keyboard shortcut to switch between English/Korean
   (default is usually Ctrl+Space or Shift+Space)

You can also use the system tray icon to switch input methods.

==========================================================
EOF
}

main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    log_info "Starting Korean input method setup"

    install_fcitx5
    configure_environment_variables
    create_autostart_entry
    print_completion_note

    log_info "Korean input setup completed"
}

main "$@"
