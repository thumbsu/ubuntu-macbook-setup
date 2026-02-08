#!/usr/bin/env bash
set -euo pipefail

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

if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)"
    exit 1
fi

info "Starting SSH server + UFW firewall setup"

# ============================================================================
# Part 1: SSH Server Configuration
# ============================================================================

info "Configuring SSH server..."

# Install openssh-server if not installed
if is_installed openssh-server; then
    ok "openssh-server already installed"
else
    info "Installing openssh-server..."
    apt-get update -qq
    apt-get install -y openssh-server
    ok "openssh-server installed"
fi

# Configure SSH
SSHD_CONFIG="/etc/ssh/sshd_config"
SOURCE_SSHD_CONFIG="$SCRIPT_DIR/../configs/sshd_config"

if [[ -f "$SOURCE_SSHD_CONFIG" ]]; then
    # Check if configs are different
    if diff -q "$SOURCE_SSHD_CONFIG" "$SSHD_CONFIG" >/dev/null 2>&1; then
        ok "sshd_config already up to date"
    else
        info "Updating sshd_config..."

        # Backup existing config
        BACKUP_FILE="/etc/ssh/sshd_config.bak.$(date +%s)"
        cp "$SSHD_CONFIG" "$BACKUP_FILE"
        ok "Backed up existing config to $BACKUP_FILE"

        # Copy new config
        cp "$SOURCE_SSHD_CONFIG" "$SSHD_CONFIG"
        ok "Updated $SSHD_CONFIG"

        # Ensure sshd prerequisites exist (needed for sshd -t validation)
        if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
            info "Generating SSH host keys..."
            ssh-keygen -A
        fi
        mkdir -p /run/sshd

        # Validate configuration
        SSHD_ERRORS=$(sshd -t 2>&1) || {
            err "SSH configuration validation failed!"
            err "$SSHD_ERRORS"
            warn "Restoring backup..."
            cp "$BACKUP_FILE" "$SSHD_CONFIG"
            exit 1
        }
        ok "SSH configuration is valid"
    fi
else
    warn "$SOURCE_SSHD_CONFIG not found"
    info "Ensuring secure defaults in existing config..."

    # Check for critical security settings
    if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
        ok "PermitRootLogin is configured"
    else
        warn "Adding PermitRootLogin no"
        echo "PermitRootLogin no" >> "$SSHD_CONFIG"
    fi

    if grep -q "^PubkeyAuthentication" "$SSHD_CONFIG"; then
        ok "PubkeyAuthentication is configured"
    else
        warn "Adding PubkeyAuthentication yes"
        echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"
    fi

    # Use KbdInteractiveAuthentication (modern replacement for deprecated challenge-response option)
    if grep -q "^KbdInteractiveAuthentication" "$SSHD_CONFIG"; then
        ok "KbdInteractiveAuthentication is configured"
    else
        warn "Adding KbdInteractiveAuthentication no"
        echo "KbdInteractiveAuthentication no" >> "$SSHD_CONFIG"
    fi
fi

# Enable and restart SSH service
info "Enabling and restarting SSH service..."
systemctl enable ssh
systemctl restart ssh

# Verify SSH is running
if systemctl is-active --quiet ssh; then
    ok "SSH service is active and running"
else
    err "SSH service failed to start"
    exit 1
fi

# ============================================================================
# Part 2: UFW Firewall Configuration
# ============================================================================

info "Configuring UFW firewall..."

# Install UFW if not installed
if is_installed ufw; then
    ok "UFW already installed"
else
    info "Installing UFW..."
    apt-get update -qq
    apt-get install -y ufw
    ok "UFW installed"
fi

# Set default policies (check first to avoid duplicates)
info "Setting default firewall policies..."
if ufw status verbose | grep -q "Default: deny (incoming)"; then
    ok "Default incoming policy already set to deny"
else
    ufw default deny incoming
    ok "Set default incoming policy to deny"
fi

if ufw status verbose | grep -q "Default: allow (outgoing)"; then
    ok "Default outgoing policy already set to allow"
else
    ufw default allow outgoing
    ok "Set default outgoing policy to allow"
fi

# Add firewall rules (check each before adding)
RULES=(
    "22/tcp:SSH"
    "80/tcp:HTTP"
    "443/tcp:HTTPS"
    "9443/tcp:Portainer"
)

info "Adding firewall rules..."
for rule_entry in "${RULES[@]}"; do
    IFS=':' read -r rule description <<< "$rule_entry"

    if ufw status | grep -q "^$rule "; then
        ok "$description ($rule) rule already exists"
    else
        info "Adding $description ($rule) rule..."
        ufw allow "$rule" comment "$description"
        ok "Added $description ($rule) rule"
    fi
done

# Enable UFW (check if already active)
if ufw status | grep -q "Status: active"; then
    ok "UFW is already active"
else
    info "Enabling UFW..."
    ufw --force enable
    ok "UFW enabled"
fi

# Show final UFW status
echo ""
info "Current UFW status:"
ufw status verbose

# ============================================================================
# Verification
# ============================================================================

echo ""
info "Verifying setup..."

# Verify SSH
if systemctl is-active --quiet ssh; then
    ok "SSH service is running"
else
    err "SSH service verification failed"
    exit 1
fi

# Verify UFW
if ufw status | grep -q "Status: active"; then
    ok "UFW is active"
else
    err "UFW verification failed"
    exit 1
fi

# ============================================================================
# Summary and Guidance
# ============================================================================

echo ""
ok "SSH server and UFW firewall setup complete!"
echo ""
info "SSH Status:"
systemctl status ssh --no-pager -l | head -n 3
echo ""
info "Firewall Rules:"
ufw status numbered
echo ""
info "SSH Key Setup Guidance:"
echo "  To set up key-based authentication:"
echo ""
echo "  1. From your client machine, copy your SSH key:"
echo "     ssh-copy-id username@server-ip"
echo ""
echo "  2. Test SSH connection:"
echo "     ssh username@server-ip"
echo ""
echo "  3. Once confirmed working, disable password authentication:"
echo "     sudo nano /etc/ssh/sshd_config"
echo "     Set: PasswordAuthentication no"
echo ""
echo "  4. Restart SSH service:"
echo "     sudo systemctl restart ssh"
echo ""
warn "IMPORTANT: Keep your current SSH session open until you've verified"
warn "key-based authentication works to avoid being locked out!"
echo ""
