# Ubuntu MacBook Pro Home Server Setup (v2)

Automated setup scripts for transforming a 2013 MacBook Pro into a dedicated Ubuntu 24.04 LTS home server with WiFi, Docker, keyboard remapping, and more.

## Overview

This project provides a complete installation and configuration pipeline for running Ubuntu Desktop 24.04 LTS on a 2013 MacBook Pro (MacBookPro11,1) as a home server. It automates hardware driver installation, system tweaks, development tools, Docker containerization, and keyboard customization—transforming dated hardware into a capable, always-on home computing platform.

Designed specifically for:
- Intel Core i5-4288U (2 cores, 4 threads)
- 16GB RAM, 500GB SSD
- Intel Iris 5100 GPU
- Broadcom BCM4360 WiFi

## Features

- **System Foundation**: Ubuntu 24.04 LTS base installation with essential tools (curl, git, vim, tmux, htop, etc.)
- **Hardware Support**: Broadcom BCM4360 WiFi driver with automatic blacklist configuration, MacBook fan control (mbpfan), power management (TLP)
- **X11 Enforcement**: Forces X11 session (disables Wayland) for compatibility with keyboard remapping
- **Server Optimization**: Disables lid-close suspend (server mode), creates 4GB swap file, sets timezone to Asia/Seoul
- **Development Tools**: Claude Code CLI for AI-powered coding assistance
- **Input Methods**: fcitx5 with Hangul support for Korean language input
- **Keyboard Remapping**: Toshy key remapper (macOS-like keybindings) + Fn key mode configuration
- **Containerization**: Docker Engine with Portainer web UI for container management
- **Security**: SSH server with hardened configuration, UFW firewall with preset rules for SSH/HTTP/HTTPS/Portainer
- **Verification**: Comprehensive verification script to check all installations and configurations

## Prerequisites

Before starting, ensure you have:

1. **Target Hardware**: 2013 MacBook Pro (MacBookPro11,1) running macOS
2. **USB Drive**: 8GB or larger USB 3.0 drive (will be erased)
3. **Internet Connection**: Wired (Ethernet) strongly recommended for initial setup
4. **macOS Access**: To create the Ubuntu boot disk
5. **Time**: ~1 hour for full setup (varies by internet speed and options selected)

## Phase 1: Create USB Boot Disk (from macOS)

### Step 1a: Download Ubuntu ISO

Download the latest Ubuntu 24.04 LTS ISO from https://ubuntu.com/download/desktop (currently 24.04.3).

Or use Terminal:

```bash
mkdir -p ~/ubuntu-setup
cd ~/ubuntu-setup

# Download latest Ubuntu 24.04 LTS point release
curl -L "https://releases.ubuntu.com/24.04/ubuntu-24.04.3-desktop-amd64.iso" -o ubuntu-24.04.3-desktop-amd64.iso

# Verify checksum (optional but recommended)
curl -L "https://releases.ubuntu.com/24.04/SHA256SUMS" -o SHA256SUMS
shasum -a 256 -c SHA256SUMS | grep ubuntu-24.04.3-desktop-amd64.iso
```

### Step 1b: Write ISO to USB Drive

Insert your USB drive and identify it:

```bash
# List disks (note the identifier like disk2, disk3, etc.)
diskutil list

# Identify your USB drive (look for EXTERNAL, usually the smallest)
# Example: /dev/disk2 (EXTERNAL, 8.0 GB)
```

**CRITICAL**: Choose the CORRECT disk number. Using the wrong disk will erase your MacBook.

Write the ISO:

```bash
# Replace diskN with your actual disk number (e.g., disk2)
DISK="disk2"

# Unmount the disk
diskutil unmountDisk "/dev/disk${DISK}"

# Write ISO to USB (this takes 5-10 minutes)
sudo dd if=ubuntu-24.04.3-desktop-amd64.iso of="/dev/rdisk${DISK}" bs=4m

# Verify completion (when it returns, you're done)
# Eject the disk when prompted or manually:
diskutil eject "/dev/disk${DISK}"
```

Keep the USB drive ready for the next phase.

## Phase 2: Install Ubuntu

### Step 2a: Boot from USB

1. Shut down the MacBook completely
2. Insert the Ubuntu USB drive
3. Power on while holding the **Option** key (Alt on some keyboards)
4. Select the USB drive (orange/external option labeled "EFI Boot")
5. Ubuntu desktop should appear in ~30 seconds

### Step 2b: Run Ubuntu Installer

1. Double-click **"Install Ubuntu"** icon on the desktop
2. Choose installation options:
   - **Language**: English
   - **Keyboard Layout**: English (US) [will be remapped later]
   - **Network**: Skip (use wired connection later)
   - **Installation Type**: **Erase disk** (this is your MacBook)
3. Select timezone when prompted (will be set to Asia/Seoul by setup)
4. Create default user account (example: `ubuntu`)
5. Complete installation and reboot

### Step 2c: Post-Install Configuration

After reboot and login:

1. **Connect to Network**:
   - Use wired Ethernet if available (Broadcom WiFi driver not yet installed)
   - Or use USB WiFi dongle as temporary solution

2. **Force X11 Session** (critical for keyboard remapping):
   - System menu → Settings → System
   - Search for "Session" or use terminal:
   ```bash
   echo "export GNOME_SHELL_SESSION_MODE=ubuntu" >> ~/.bashrc
   ```
   - At login screen, click username, then select **"Ubuntu on Xorg"** below password field
   - This is REQUIRED before running setup scripts

## Phase 3: Run Setup Scripts

### Step 3a: Clone Repository

In a terminal on the Ubuntu machine:

```bash
cd ~
git clone https://github.com/yourusername/ubuntu-macbook-setup.git
cd ubuntu-macbook-setup
chmod +x *.sh scripts/*.sh extras/*.sh
```

### Step 3b: Run Main Setup

Start the interactive setup orchestrator:

```bash
sudo ./setup.sh
```

The setup will prompt you before each of 8 steps:

```
[01/08] System Update & Base Packages → [Y/n/s]
[02/08] System Tweaks → [Y/n/s]
[03/08] MacBook Drivers → [Y/n/s]
[04/08] Claude Code CLI → [Y/n/s]
[05/08] Korean Input → [Y/n/s]
[06/08] Keyboard Remap → [Y/n/s]
[07/08] Docker & Portainer → [Y/n/s]
[08/08] SSH & Firewall → [Y/n/s]
```

**Response options**:
- **Y** or **Enter**: Execute this step
- **n**: Skip this step
- **s**: Skip this and all remaining steps

### Step 3c: Reboot After Step 3

After MacBook Drivers (step 3) completes, you MUST reboot for WiFi and X11 changes to take effect:

```bash
# The script will offer to reboot automatically
# Or manually:
sudo reboot
```

After reboot, resume where you left off:

```bash
sudo ./setup.sh --from claude-code
```

This resumes from step 4 (Claude Code CLI).

### Alternative: Automatic Mode

To skip all prompts and run everything automatically:

```bash
sudo ./setup.sh --auto
```

Or run only specific scripts:

```bash
# Install only Docker
sudo ./setup.sh --only docker

# Run Docker + SSH/Firewall
sudo ./setup.sh --from docker

# See all available names
sudo ./setup.sh --list
```

## Phase 4: Post-Setup Verification

After setup completes and you've rebooted, verify everything works:

```bash
./verify.sh
```

This checks:
- All packages installed
- System tweaks applied (X11, lid settings, timezone, swap)
- WiFi driver loaded
- Services running (ssh, docker, fan control, power management)
- Firewall rules configured
- No forbidden patterns in scripts

Expected output:
```
✓ PASS:  47
✗ FAIL:  0
~ WARN:  2
```

Review any FAIL results and fix if needed.

### Manual Post-Setup Checks

1. **WiFi Connection**:
   ```bash
   # Check if WiFi driver loaded
   lsmod | grep wl

   # Check WiFi status
   nmcli device status
   ```

2. **Docker Working**:
   ```bash
   docker ps
   docker images
   ```

3. **Portainer Access**:
   - Open browser: `https://localhost:9443`
   - Create admin account
   - Manage containers

4. **SSH Access**:
   ```bash
   ssh username@localhost -p 22
   ```

5. **Keyboard Remapping**:
   - Check Toshy status:
   ```bash
   ~/toshy/toshy-services-status
   ```

6. **Korean Input** (if installed):
   - Press Ctrl+Space to toggle input method
   - Type Korean characters

## Script Details

| # | Name | File | Runs As | Purpose |
|---|------|------|---------|---------|
| 01 | System Update & Base Packages | `01-system-update.sh` | root | apt update/upgrade, essential tools, kernel headers, DKMS |
| 02 | System Tweaks | `02-system-tweaks.sh` | root | X11 enforcement, lid settings, timezone, 4GB swap |
| 03 | MacBook Drivers | `03-macbook-drivers.sh` | root | Broadcom WiFi (bcm4360), mbpfan, TLP power management |
| 04 | Claude Code CLI | `04-claude-code.sh` | user | Claude Code AI assistant installation to ~/.local/bin |
| 05 | Korean Input | `05-korean-input.sh` | root | fcitx5 + Hangul IME, input environment variables |
| 06 | Keyboard Remap | `06-keyboard-remap.sh` | dual | Toshy installer (user) + Fn key config (root) |
| 07 | Docker & Portainer | `07-docker.sh` | root | Docker Engine, Docker Compose, Portainer CE container |
| 08 | SSH & Firewall | `08-ssh-firewall.sh` | root | OpenSSH hardened config, UFW firewall rules |

**Execution Types**:
- **root**: Runs with `sudo`
- **user**: Runs as your regular user
- **dual**: Runs twice (as user for Toshy, then as root for Fn key)

## Extras

### Obsidian + Google Drive Integration

After main setup, optionally install Obsidian with Google Drive sync:

```bash
bash extras/setup-obsidian.sh
```

This script:
1. Installs Obsidian via Snap
2. Installs rclone for cloud sync
3. Configures Google Drive remote
4. Creates systemd service for automatic mounting

**Run this as your regular user** (not with sudo).

## Known Issues & Troubleshooting

### Black Screen / No Desktop After Login

**Issue**: Ubuntu boots but shows black screen or drops to TTY.

**Solution**:
1. At login screen, click your username
2. Select **"Ubuntu on Xorg"** from session dropdown (bottom right)
3. Enter password
4. Desktop should appear

If dropdown is missing:
```bash
# From TTY (Ctrl+Alt+F2)
sudo apt install gnome-session
sudo reboot
```

### WiFi Not Working

**Issue**: No WiFi networks visible or connection fails.

**Check driver status**:
```bash
lsmod | grep wl
```

If no output, Broadcom driver not loaded. Troubleshoot:

```bash
# Check blacklist is correct
cat /etc/modprobe.d/blacklist-broadcom-wireless.conf

# Check DKMS compilation
dkms status broadcom-sta-dkms

# If errors, rebuild:
sudo dkms remove broadcom-sta-dkms --all
sudo dkms install broadcom-sta-dkms
sudo modprobe wl
sudo reboot
```

Use wired Ethernet as fallback.

### Keyboard Remapping Not Working

**Issue**: Key remapping not active, macOS-style keys not working.

**Toshy troubleshooting**:
```bash
# Check if Toshy is running
~/toshy/toshy-services-status

# If not running, restart
systemctl --user restart toshy

# Check logs
journalctl --user -u toshy -n 50
```

**Fn key not working**:
```bash
# Verify configuration
cat /etc/modprobe.d/hid_apple.conf | grep fnmode

# Should show: options hid_apple fnmode=2
# If not, reboot required
```

After any changes, reboot:
```bash
sudo reboot
```

### Docker Daemon Issues

**Issue**: `docker ps` fails or shows permission denied.

**Solution**:
```bash
# Check if Docker is running
systemctl status docker

# Restart Docker
sudo systemctl restart docker

# Verify user is in docker group
id | grep docker

# If not, add user (requires reboot):
sudo usermod -aG docker $USER
```

### SSH Connection Refused

**Issue**: Cannot SSH into MacBook from network.

**Check firewall**:
```bash
sudo ufw status
# Should show:
# 22/tcp  ALLOW

# If not, enable:
sudo ufw allow 22/tcp
sudo ufw enable
```

**Check SSH service**:
```bash
sudo systemctl status sshd
sudo systemctl start sshd
```

### High Fan Noise

**Issue**: Fan running constantly or too loud.

**mbpfan tuning**:
```bash
# Check mbpfan status
sudo systemctl status mbpfan

# View current configuration
cat /etc/mbpfan.conf

# Adjust thresholds in /etc/mbpfan.conf if needed
# Restart after changes:
sudo systemctl restart mbpfan
```

## Lessons Learned (v1 → v2)

### What v1 Got Wrong

1. **Wayland Wars**: Wayland + keyboard remapping = disaster. v2 forces X11 from start.
2. **Silent Failures**: Many scripts failed silently. v2 has explicit error handling and logging.
3. **Reboot Timing**: WiFi needs reboot AFTER driver installation. v2 prompts for reboot at right time.
4. **Docker Group**: User not in docker group, had to use sudo for docker. v2 adds user to group.
5. **No Verification**: Users didn't know what worked. v2 includes `verify.sh` script.

### v2 Improvements

- **Idempotent**: Scripts can be run multiple times safely
- **Resumable**: `--from` flag lets you resume after reboot
- **Checkpoints**: Clear success messages with progress tracking
- **Logging**: All output logged to `/var/log/ubuntu-setup.log`
- **Flexible**: `--auto`, `--only`, `--list` options for different workflows
- **Verified**: `verify.sh` checks 50+ installation points

## Log Files

All setup output is logged to:

```bash
/var/log/ubuntu-setup.log
```

View recent activity:
```bash
tail -50 /var/log/ubuntu-setup.log
```

View entire log:
```bash
cat /var/log/ubuntu-setup.log
```

## Next Steps After Setup

1. **Configure Services**:
   - Set SSH public key authentication (disable password auth)
   - Configure Docker volumes and networks
   - Start Portainer and create containers

2. **Customize System**:
   - Add static IP to `/etc/netplan/` if needed
   - Configure cron jobs for backups
   - Set up monitoring/alerting

3. **Development**:
   - Clone your projects from GitHub
   - Set up git SSH keys
   - Configure development environment

4. **Obsidian Integration**:
   - Run `extras/setup-obsidian.sh` for note-taking with cloud sync
   - Create your vault or sync existing one

## System Information

**Ubuntu Version**: 24.04 LTS (Noble Numbat)
**Target MacBook**: MacBook Pro 11,1 (Mid 2013)
**Processor**: Intel Core i5-4288U @ 2.60GHz (2 cores, 4 threads)
**RAM**: 16GB DDR3L
**Storage**: 500GB SSD (SATA)
**GPU**: Intel Iris Graphics 5100
**WiFi**: Broadcom BCM4360 (14e4:43ec)

## Support & Issues

If you encounter problems:

1. **Check Known Issues** section above
2. **Review `/var/log/ubuntu-setup.log`** for error details
3. **Run `./verify.sh`** to identify missing components
4. **Try `--only` flag** to re-run specific step:
   ```bash
   sudo ./setup.sh --only docker
   ```

## Hardware Notes

### MacBook Pro 11,1 (Mid 2013)

This specific model has several quirks:

- **Broadcom BCM4360 WiFi**: Requires broadcom-sta-dkms driver
- **Rapid Storage Technology**: SSD works fine with standard drivers
- **Thunderbolt Port**: Works as USB 3.0
- **FaceTime HD Camera**: Supported via uvcvideo kernel module
- **Battery**: Degraded (normal for 2013 hardware) but TLP helps
- **GPU**: Intel Iris shares system RAM, 4GB allocated on this system

### Fan/Thermal Management

The MacBook tends to run warm on Linux. The setup includes:

- **mbpfan**: Dynamic fan control based on temperature sensors
- **TLP**: CPU frequency scaling and power management
- **Swap**: 4GB prevents system from thrashing when low on RAM

Monitor temperatures:
```bash
sensors
```

Monitor fan speed:
```bash
cat /sys/class/hwmon/hwmon*/fan1_input
```

## Contributing

To improve this setup:

1. Test changes on a 2013 MacBook Pro (or similar hardware)
2. Ensure all scripts are idempotent (safe to run multiple times)
3. Update `verify.sh` if adding new checks
4. Keep scripts in `scripts/` directory, numbered in execution order
5. Document any new steps in this README

## License

MIT - Free to use and modify. See LICENSE file for details.

## Changelog

### v2 (Current)
- Complete rewrite with focus on reliability and debugging
- Added interactive orchestrator with prompts
- Added `--auto`, `--only`, `--from`, `--list` options
- Added comprehensive `verify.sh` script
- Forced X11 at start (before other configs)
- Better error handling and logging
- Idempotent scripts (safe to re-run)
- Added Obsidian/Google Drive integration option

### v1 (Legacy)
- Initial MacBook Pro → Ubuntu setup scripts
- Basic driver installation and configuration
- Limited error handling and feedback

---

**Created**: 2024
**Last Updated**: 2026-02-08
**Tested On**: MacBook Pro 11,1 (Mid 2013), Ubuntu 24.04 LTS
