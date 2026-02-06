#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo "=== UFW Firewall Setup ==="
echo

# Install UFW
install_ufw() {
    echo "[1/4] Installing UFW..."

    if ! command -v ufw &>/dev/null; then
        apt-get install -y ufw
        echo "UFW installed"
    else
        echo "UFW already installed"
    fi
    echo
}

# Reset and configure UFW
configure_ufw() {
    echo "[2/4] Configuring UFW..."

    echo "Resetting UFW to defaults..."
    ufw --force reset

    echo "Setting default policies..."
    ufw default deny incoming
    ufw default allow outgoing

    echo
}

# Add firewall rules
add_firewall_rules() {
    echo "[3/4] Adding firewall rules..."

    echo "Allowing SSH (22/tcp)..."
    ufw allow 22/tcp comment 'SSH'

    echo "Allowing HTTP (80/tcp)..."
    ufw allow 80/tcp comment 'HTTP'

    echo "Allowing HTTPS (443/tcp)..."
    ufw allow 443/tcp comment 'HTTPS'

    echo "Allowing Portainer (9443/tcp)..."
    ufw allow 9443/tcp comment 'Portainer'

    echo
}

# Enable UFW
enable_ufw() {
    echo "[4/4] Enabling UFW..."

    ufw --force enable

    echo "UFW enabled and active"
    echo
}

# Display status
show_status() {
    echo "=== UFW Status ==="
    ufw status verbose
    echo

    echo "=== Open Ports Summary ==="
    echo "  SSH:       22/tcp"
    echo "  HTTP:      80/tcp"
    echo "  HTTPS:     443/tcp"
    echo "  Portainer: 9443/tcp"
    echo
    echo "Default policies:"
    echo "  Incoming: DENY"
    echo "  Outgoing: ALLOW"
    echo
}

# Main execution
main() {
    install_ufw
    configure_ufw
    add_firewall_rules
    enable_ufw
    show_status

    echo "=== UFW Firewall Setup Complete ==="
    echo
    echo "To manage firewall rules:"
    echo "  sudo ufw status verbose    # View current rules"
    echo "  sudo ufw allow PORT/tcp    # Allow a port"
    echo "  sudo ufw delete allow PORT # Remove a rule"
    echo "  sudo ufw disable           # Disable firewall"
    echo
}

main
