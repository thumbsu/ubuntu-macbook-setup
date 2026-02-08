#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# extras/setup-obsidian.sh - Obsidian + Google Drive (rclone)
# Run AFTER initial setup + reboot, as regular user
# Usage: bash extras/setup-obsidian.sh
# ============================================================

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

if [[ $EUID -eq 0 ]]; then
    err "Do NOT run this script as root/sudo. Run as your regular user."
    exit 1
fi

echo -e "\n${BLUE}=== Obsidian + Google Drive Setup ===${NC}\n"

# --- 1. Install Obsidian via Snap ---
info "Checking Obsidian installation..."
if snap list obsidian &>/dev/null 2>&1; then
    ok "Obsidian already installed via snap"
else
    info "Installing Obsidian via snap..."
    sudo snap install obsidian --classic
    ok "Obsidian installed"
fi

# --- 2. Install rclone ---
info "Checking rclone installation..."
if command -v rclone &>/dev/null; then
    ok "rclone already installed ($(rclone version --check 2>/dev/null | head -1 || rclone --version | head -1))"
else
    info "Installing rclone..."
    curl -fsSL https://rclone.org/install.sh | sudo bash
    ok "rclone installed"
fi

# --- 3. Configure Google Drive mount ---
MOUNT_DIR="${HOME}/GoogleDrive"
SYSTEMD_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SYSTEMD_DIR}/rclone-gdrive.service"

if rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
    ok "rclone 'gdrive' remote already configured"
else
    warn "rclone 'gdrive' remote not configured yet."
    echo ""
    echo "  Run: rclone config"
    echo "  Choose: New remote → Name: gdrive → Type: Google Drive"
    echo "  Follow the OAuth prompts in your browser."
    echo ""
    read -rp "Configure now? [Y/n] " ans
    if [[ "${ans:-y}" =~ ^[Yy]$ ]]; then
        rclone config
    else
        warn "Skipping rclone config. Run 'rclone config' manually later."
    fi
fi

# --- 4. Create mount point ---
if [[ ! -d "$MOUNT_DIR" ]]; then
    mkdir -p "$MOUNT_DIR"
    ok "Created mount point: $MOUNT_DIR"
else
    ok "Mount point exists: $MOUNT_DIR"
fi

# --- 5. Enable fuse allow_other (required for --allow-other flag) ---
if grep -q "^#user_allow_other" /etc/fuse.conf 2>/dev/null; then
    sudo sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf
    ok "Enabled user_allow_other in /etc/fuse.conf"
elif grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
    ok "user_allow_other already enabled in /etc/fuse.conf"
else
    echo "user_allow_other" | sudo tee -a /etc/fuse.conf >/dev/null
    ok "Added user_allow_other to /etc/fuse.conf"
fi

# --- 6. Create systemd user service for auto-mount ---
mkdir -p "$SYSTEMD_DIR"

if [[ -f "$SERVICE_FILE" ]]; then
    ok "rclone systemd service already exists"
else
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=rclone mount Google Drive
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount gdrive: ${MOUNT_DIR} \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-size 1G \\
    --dir-cache-time 72h \\
    --poll-interval 15s \\
    --allow-other \\
    --allow-non-empty
ExecStop=/bin/fusermount -u ${MOUNT_DIR}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
    ok "Created systemd user service: $SERVICE_FILE"

    # Enable lingering for user services to start at boot
    sudo loginctl enable-linger "$USER"

    systemctl --user daemon-reload
    systemctl --user enable rclone-gdrive.service
    ok "Service enabled (will auto-mount at login)"
fi

# --- 7. Start mount if remote is configured ---
if rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        ok "Google Drive already mounted at $MOUNT_DIR"
    else
        info "Starting Google Drive mount..."
        systemctl --user start rclone-gdrive.service
        sleep 2
        if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
            ok "Google Drive mounted at $MOUNT_DIR"
        else
            warn "Mount may take a moment. Check: ls $MOUNT_DIR"
        fi
    fi
fi

# --- 8. Print Obsidian vault instructions ---
echo ""
echo -e "${GREEN}=== Next Steps ===${NC}"
echo ""
echo "  1. Open Obsidian (from app menu or: obsidian &)"
echo "  2. 'Open folder as vault'"
echo "  3. Navigate to: ${MOUNT_DIR}/Obsidian/second-brain"
echo ""
echo "  Plugins (Smart Connections etc.) sync automatically"
echo "  via the vault's .obsidian/ folder in Google Drive."
echo ""
echo -e "${YELLOW}Note:${NC} If Google Drive isn't mounted yet:"
echo "  - Check: systemctl --user status rclone-gdrive"
echo "  - Manual mount: rclone mount gdrive: ~/GoogleDrive --vfs-cache-mode writes &"
echo ""

ok "Setup complete!"
