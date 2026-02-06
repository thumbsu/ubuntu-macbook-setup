# Ubuntu Desktop 24.04 LTS - MacBook Pro 2013 Setup

Automated setup scripts for installing and configuring Ubuntu Desktop 24.04 LTS on a 2013 MacBook Pro (MacBookPro11,1).

**Purpose**: Home server (Docker) + Development environment

## What's Included

| Script | Description |
|--------|-------------|
| `01-system-update.sh` | System update + essential packages |
| `02-macbook-drivers.sh` | Broadcom WiFi, fan control (mbpfan), power management |
| `03-korean-input.sh` | fcitx5 + Hangul input method |
| `04-docker.sh` | Docker Engine + Compose + Portainer CE |
| `05-dev-tools.sh` | Git, Node.js (nvm), Python 3, VS Code, ripgrep, etc. |
| `06-ssh.sh` | SSH server with key authentication |
| `07-firewall.sh` | UFW firewall (SSH, HTTP, HTTPS, Portainer) |
| `08-system-tweaks.sh` | Lid switch, timezone, swap, auto-update disable |
| `09-keyboard-remap.sh` | Toshy (macOS keybindings) + MacBook Fn key mode |

## Prerequisites

1. Ubuntu Desktop 24.04 LTS freshly installed on MacBook Pro 2013
2. Internet connection (Ethernet recommended, WiFi driver installed in script 02)
3. Terminal access

## Installation

### Step 1: Create USB Boot Disk (on macOS)

Download Ubuntu Desktop 24.04 LTS ISO from https://ubuntu.com/download/desktop

```bash
# Find your USB disk number
diskutil list

# Unmount (replace N with your disk number)
diskutil unmountDisk /dev/diskN

# Write ISO to USB
sudo dd if=~/Downloads/ubuntu-24.04.2-desktop-amd64.iso of=/dev/rdiskN bs=4m status=progress

# Eject
diskutil eject /dev/diskN
```

> **Warning**: Double-check the disk number. Wrong disk = data loss.

### Step 2: Install Ubuntu on MacBook Pro

1. Power off MacBook Pro
2. Insert USB
3. Hold **Option (Alt)** key and power on
4. Select **EFI Boot**
5. Choose "Install Ubuntu"
6. Select "Erase disk and install Ubuntu"
7. Complete installation and reboot

### Step 3: Run Setup Scripts

```bash
# Install git
sudo apt update && sudo apt install -y git

# Clone this repo
git clone https://github.com/thumbsu/ubuntu-macbook-setup.git
cd ubuntu-macbook-setup

# Make executable
chmod +x setup.sh scripts/*.sh

# Run all scripts
sudo ./setup.sh

# Reboot
sudo reboot
```

## Usage

### Run all scripts

```bash
sudo ./setup.sh
```

### Run a specific script

```bash
sudo ./setup.sh --only docker
sudo ./setup.sh --only ssh
sudo ./setup.sh --only firewall
```

### List available scripts

```bash
sudo ./setup.sh --list
```

### View logs

```bash
cat /var/log/ubuntu-setup.log
```

## Post-Installation

### SSH Key Setup

After running the scripts, set up SSH key authentication from your client machine:

```bash
# From your local machine (e.g., Mac)
ssh-copy-id username@macbook-pro-ip

# Then on the MacBook Pro, disable password auth
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### Korean Input

1. Log out and back in after running script 03
2. Open Fcitx5 Configuration
3. Add "Hangul" input method
4. Set toggle shortcut (default: Ctrl+Space)

### Keyboard Remapping (Toshy)

After reboot:

1. Enable "Toshy" extension in GNOME Extensions (required for Wayland)
2. Check status: `toshy-config-start`
3. Cmd+C/V/Z etc. should work like macOS
4. F1-F12 keys work as function keys by default (hold Fn for media keys)

### Portainer

Access Portainer web UI at: `https://<macbook-pro-ip>:9443`

Create an admin account on first access.

### Git Configuration

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

## Hardware Notes (MacBook Pro 2013)

- **WiFi**: Broadcom BCM4360 - requires `bcmwl-kernel-source`
- **Graphics**: Intel Iris (iris driver, works out of box)
- **Fan**: Controlled via `mbpfan` service
- **Lid**: Configured to stay awake when closed (server mode)
- **Keyboard**: Toshy remaps keys to macOS layout; Fn key set to function key mode

## Idempotency

All scripts are safe to run multiple times. On re-run they will:
- Skip already-installed packages
- Skip already-configured settings
- Not reset existing firewall rules
- Not overwrite SSH config if unchanged
- Not redeploy running containers

## File Structure

```
ubuntu-macbook-setup/
├── README.md
├── setup.sh                   # Main entry point
├── scripts/
│   ├── 01-system-update.sh
│   ├── 02-macbook-drivers.sh
│   ├── 03-korean-input.sh
│   ├── 04-docker.sh
│   ├── 05-dev-tools.sh
│   ├── 06-ssh.sh
│   ├── 07-firewall.sh
│   ├── 08-system-tweaks.sh
│   └── 09-keyboard-remap.sh
├── configs/
│   ├── sshd_config
│   └── docker-compose.yml
└── .gitignore
```

## License

MIT
