#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo "=== UFW Firewall Setup ==="
echo

# Required ports
REQUIRED_RULES=(
    "22/tcp:SSH"
    "80/tcp:HTTP"
    "443/tcp:HTTPS"
    "9443/tcp:Portainer"
)

# Install UFW
install_ufw() {
    echo "[1/3] Installing UFW..."

    if ! command -v ufw &>/dev/null; then
        apt-get install -y ufw
        echo "UFW installed"
    else
        echo "UFW already installed"
    fi
    echo
}

# Configure defaults and add rules (idempotent)
configure_ufw() {
    echo "[2/3] Configuring UFW rules..."

    # Set default policies (idempotent - ufw handles re-setting gracefully)
    ufw default deny incoming
    ufw default allow outgoing

    # Add rules only if not already present
    for rule_entry in "${REQUIRED_RULES[@]}"; do
        local port_proto="${rule_entry%%:*}"
        local comment="${rule_entry##*:}"

        if ufw status | grep -q "${port_proto}"; then
            echo "Rule already exists: ${port_proto} (${comment})"
        else
            echo "Adding rule: ${port_proto} (${comment})..."
            ufw allow "${port_proto}" comment "${comment}"
        fi
    done

    echo
}

# Enable UFW
enable_ufw() {
    echo "[3/3] Enabling UFW..."

    if ufw status | grep -q "Status: active"; then
        echo "UFW already active"
    else
        ufw --force enable
        echo "UFW enabled"
    fi
    echo
}

# Display status
show_status() {
    echo "=== UFW Status ==="
    ufw status verbose
    echo

    echo "=== Expected Open Ports ==="
    for rule_entry in "${REQUIRED_RULES[@]}"; do
        local port_proto="${rule_entry%%:*}"
        local comment="${rule_entry##*:}"
        local port="${port_proto%%/*}"
        printf "  %-12s %s\n" "${comment}:" "${port_proto}"
    done
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
