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

info "Starting Docker Engine + Docker Compose + Portainer CE setup"

# Step 1: Install Docker
if docker info >/dev/null 2>&1; then
    ok "Docker already installed and running"
else
    info "Installing Docker Engine..."

    # Install prerequisites
    info "Installing prerequisites..."
    apt-get update -qq
    apt-get install -y ca-certificates curl

    # Add Docker's official GPG key
    info "Adding Docker GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    info "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update and install Docker
    info "Installing Docker packages..."
    apt-get update -qq
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    ok "Docker installed successfully"
fi

# Step 2: Add user to docker group
if [[ -n "${SUDO_USER:-}" ]]; then
    if id "$SUDO_USER" | grep -q '\bdocker\b'; then
        ok "$SUDO_USER already in docker group"
    else
        info "Adding $SUDO_USER to docker group..."
        usermod -aG docker "$SUDO_USER"
        ok "$SUDO_USER added to docker group"
        warn "User will need to log out and back in for group changes to take effect"
    fi
else
    warn "SUDO_USER not set, cannot add user to docker group"
fi

# Step 3: Enable and start Docker service
info "Ensuring Docker service is enabled and running..."
systemctl enable docker
systemctl start docker
ok "Docker service enabled and started"

# Verify Docker is working
if docker info >/dev/null 2>&1; then
    ok "Docker is running correctly"
else
    err "Docker installed but not responding"
    exit 1
fi

# Step 4: Deploy Portainer CE
info "Setting up Portainer CE..."

PORTAINER_DIR="/opt/portainer"
COMPOSE_FILE="$PORTAINER_DIR/docker-compose.yml"
SOURCE_COMPOSE="$SCRIPT_DIR/../configs/docker-compose.yml"

# Check if portainer container exists
if docker ps -a --filter name=portainer --format '{{.Names}}' | grep -q '^portainer$'; then
    info "Portainer container already exists"

    # Check if it's running
    if docker ps --filter name=portainer --format '{{.Names}}' | grep -q '^portainer$'; then
        ok "Portainer is already running"
    else
        info "Starting existing Portainer container..."
        docker start portainer
        ok "Portainer started"
    fi
else
    info "Deploying new Portainer container..."

    # Create Portainer directory
    mkdir -p "$PORTAINER_DIR"

    # Copy docker-compose.yml
    if [[ -f "$SOURCE_COMPOSE" ]]; then
        cp "$SOURCE_COMPOSE" "$COMPOSE_FILE"
        ok "Copied docker-compose.yml to $PORTAINER_DIR"
    else
        warn "$SOURCE_COMPOSE not found, creating basic compose file"

        # Create basic docker-compose.yml
        cat > "$COMPOSE_FILE" <<'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    ports:
      - "9443:9443"

volumes:
  portainer_data:
EOF
        ok "Created basic docker-compose.yml"
    fi

    # Deploy Portainer
    info "Starting Portainer with docker compose..."
    docker compose -f "$COMPOSE_FILE" up -d
    ok "Portainer deployed successfully"
fi

# Step 5: Verify installation
echo ""
info "Verifying installation..."

if docker info >/dev/null 2>&1; then
    ok "Docker is running"
else
    err "Docker verification failed"
    exit 1
fi

if docker ps --filter name=portainer --format '{{.Names}}' | grep -q '^portainer$'; then
    ok "Portainer is running"
else
    err "Portainer verification failed"
    exit 1
fi

# Print summary
echo ""
ok "Docker and Portainer setup complete!"
echo ""
info "Docker Info:"
docker version --format '  Version: {{.Server.Version}}'
docker compose version
echo ""
info "Portainer Info:"
echo "  Container: $(docker ps --filter name=portainer --format '{{.Names}} ({{.Status}})')"
echo "  Access: https://localhost:9443"
echo ""
warn "First-time Portainer setup:"
echo "  1. Open https://localhost:9443 in your browser"
echo "  2. Create an admin account (username + password)"
echo "  3. Select 'Get Started' to manage local Docker environment"
echo ""

if [[ -n "${SUDO_USER:-}" ]]; then
    warn "Remember: $SUDO_USER needs to log out and back in for docker group membership to take effect"
fi
