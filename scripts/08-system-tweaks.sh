#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo "=== System Tweaks for Server/Headless Use ==="
echo

# Lid switch configuration
configure_lid_switch() {
    echo "[1/5] Configuring lid switch behavior..."

    local LOGIND_CONF="/etc/systemd/logind.conf"

    if ! grep -q "^HandleLidSwitch=ignore" "$LOGIND_CONF"; then
        sed -i 's/^#\?HandleLidSwitch=.*/HandleLidSwitch=ignore/' "$LOGIND_CONF"

        # Add if not exists
        if ! grep -q "^HandleLidSwitch=" "$LOGIND_CONF"; then
            echo "HandleLidSwitch=ignore" >> "$LOGIND_CONF"
        fi

        echo "Set HandleLidSwitch=ignore"
    else
        echo "HandleLidSwitch already set to ignore"
    fi

    if ! grep -q "^HandleLidSwitchExternalPower=ignore" "$LOGIND_CONF"; then
        sed -i 's/^#\?HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' "$LOGIND_CONF"

        # Add if not exists
        if ! grep -q "^HandleLidSwitchExternalPower=" "$LOGIND_CONF"; then
            echo "HandleLidSwitchExternalPower=ignore" >> "$LOGIND_CONF"
        fi

        echo "Set HandleLidSwitchExternalPower=ignore"
    else
        echo "HandleLidSwitchExternalPower already set to ignore"
    fi

    # NOTE: Do NOT restart systemd-logind here!
    # It kills all active sessions and kicks user to login screen.
    # Changes take effect on next reboot.
    echo "Lid switch configured (takes effect after reboot)"
    echo
}

# Timezone configuration
configure_timezone() {
    echo "[2/5] Configuring timezone..."

    local CURRENT_TZ=$(timedatectl show --property=Timezone --value)

    if [ "$CURRENT_TZ" != "Asia/Seoul" ]; then
        timedatectl set-timezone Asia/Seoul
        echo "Timezone set to Asia/Seoul"
    else
        echo "Timezone already set to Asia/Seoul"
    fi

    echo "Current time: $(date)"
    echo
}

# Disable automatic updates
disable_automatic_updates() {
    echo "[3/5] Disabling automatic updates..."

    # Stop and disable unattended-upgrades
    if systemctl is-active --quiet unattended-upgrades; then
        systemctl stop unattended-upgrades
        echo "Stopped unattended-upgrades service"
    fi

    if systemctl is-enabled --quiet unattended-upgrades 2>/dev/null; then
        systemctl disable unattended-upgrades
        echo "Disabled unattended-upgrades service"
    fi

    # Disable apt daily timers
    if systemctl is-active --quiet apt-daily.timer; then
        systemctl stop apt-daily.timer
        systemctl disable apt-daily.timer
        echo "Disabled apt-daily.timer"
    fi

    if systemctl is-active --quiet apt-daily-upgrade.timer; then
        systemctl stop apt-daily-upgrade.timer
        systemctl disable apt-daily-upgrade.timer
        echo "Disabled apt-daily-upgrade.timer"
    fi

    echo "Automatic updates disabled"
    echo
}

# Configure swap
configure_swap() {
    echo "[4/5] Configuring swap..."

    if swapon --show | grep -q "/swapfile"; then
        echo "Swap already configured and active"
        swapon --show
    else
        local SWAPFILE="/swapfile"

        if [ ! -f "$SWAPFILE" ]; then
            echo "Creating 4GB swapfile..."
            fallocate -l 4G "$SWAPFILE"
            chmod 600 "$SWAPFILE"
            mkswap "$SWAPFILE"
            swapon "$SWAPFILE"

            # Add to fstab if not present
            if ! grep -q "$SWAPFILE" /etc/fstab; then
                echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
                echo "Added swapfile to /etc/fstab"
            fi

            echo "Swapfile created and activated"
        else
            echo "Swapfile exists, ensuring it's active..."
            chmod 600 "$SWAPFILE"
            swapon "$SWAPFILE" 2>/dev/null || true

            if ! grep -q "$SWAPFILE" /etc/fstab; then
                echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
            fi
        fi

        swapon --show
    fi
    echo
}

# Force X11 session instead of Wayland (more compatible with 2013 MacBook)
configure_xorg_session() {
    echo "[5/6] Configuring GDM to use X11 instead of Wayland..."

    local GDM_CONF="/etc/gdm3/custom.conf"

    if [ ! -f "$GDM_CONF" ]; then
        echo "GDM config not found (not using GDM?), skipping"
        echo
        return 0
    fi

    if grep -q "^WaylandEnable=false" "$GDM_CONF"; then
        echo "Wayland already disabled in GDM"
    else
        # Uncomment or add WaylandEnable=false
        if grep -q "^#.*WaylandEnable" "$GDM_CONF"; then
            sed -i 's/^#.*WaylandEnable.*/WaylandEnable=false/' "$GDM_CONF"
        else
            # Add under [daemon] section
            sed -i '/^\[daemon\]/a WaylandEnable=false' "$GDM_CONF"
        fi
        echo "Disabled Wayland in GDM (will use X11/Xorg)"
    fi
    echo
}

# GRUB configuration
configure_grub() {
    echo "[6/6] Checking GRUB configuration..."

    local GRUB_CONFIG="/etc/default/grub"

    if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' "$GRUB_CONFIG"; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/' "$GRUB_CONFIG"
        echo "Updated GRUB_CMDLINE_LINUX_DEFAULT"

        echo "Updating GRUB..."
        update-grub
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT already set correctly"
    fi
    echo
}

# Print summary
print_summary() {
    echo "=== System Tweaks Summary ==="
    echo
    echo "1. Lid Switch:"
    echo "   - HandleLidSwitch=ignore"
    echo "   - HandleLidSwitchExternalPower=ignore"
    echo "   - Laptop will not suspend when lid is closed"
    echo
    echo "2. Timezone:"
    echo "   - Set to Asia/Seoul"
    echo "   - Current time: $(date)"
    echo
    echo "3. Automatic Updates:"
    echo "   - unattended-upgrades: disabled"
    echo "   - apt-daily.timer: disabled"
    echo "   - apt-daily-upgrade.timer: disabled"
    echo
    echo "4. Swap:"
    if swapon --show | grep -q "/swapfile"; then
        echo "   - 4GB swapfile active at /swapfile"
        swapon --show | tail -n +2
    else
        echo "   - No swap configured"
    fi
    echo
    echo "5. Display Session:"
    echo "   - Wayland disabled, using X11/Xorg (better 2013 MacBook compatibility)"
    echo
    echo "6. GRUB:"
    echo "   - GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash\""
    echo
}

# Main execution
main() {
    configure_lid_switch
    configure_timezone
    disable_automatic_updates
    configure_swap
    configure_xorg_session
    configure_grub
    print_summary

    echo "=== System Tweaks Complete ==="
    echo
    echo "NOTES:"
    echo "  - Lid switch & Wayland changes take effect after reboot"
    echo "  - GRUB changes take effect on next boot"
    echo "  - Swap is active immediately and persistent across reboots"
    echo
}

main
