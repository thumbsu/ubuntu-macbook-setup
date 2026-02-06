#!/usr/bin/env bash
set -euo pipefail

# Docker Engine + Portainer installation

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

remove_old_docker() {
    log_info "Removing old Docker packages if present..."

    local old_packages=(
        docker.io
        docker-doc
        docker-compose
        podman-docker
        containerd
        runc
    )

    for pkg in "${old_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*${pkg}"; then
            log_info "Removing $pkg..."
            apt remove -y "$pkg" || true
        fi
    done

    log_info "Old Docker packages removed"
}

add_docker_repository() {
    log_info "Adding Docker's official GPG key and repository..."

    # Create keyrings directory if it doesn't exist
    install -m 0755 -d /etc/apt/keyrings

    # Add Docker's official GPG key
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    else
        log_info "Docker GPG key already exists"
    fi

    # Add Docker repository
    local repo_file="/etc/apt/sources.list.d/docker.list"
    if [[ ! -f "$repo_file" ]]; then
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            tee "$repo_file" > /dev/null
    else
        log_info "Docker repository already configured"
    fi

    apt update

    log_info "Docker repository added successfully"
}

install_docker() {
    log_info "Installing Docker Engine and related packages..."

    local packages=(
        docker-ce
        docker-ce-cli
        containerd.io
        docker-buildx-plugin
        docker-compose-plugin
    )

    DEBIAN_FRONTEND=noninteractive apt install -y "${packages[@]}"

    log_info "Docker packages installed successfully"
}

configure_docker_service() {
    log_info "Enabling and starting Docker service..."

    systemctl enable docker
    systemctl start docker

    log_info "Docker service started successfully"
}

add_user_to_docker_group() {
    local target_user="${SUDO_USER:-}"

    if [[ -z "$target_user" ]]; then
        log_error "Cannot determine user to add to docker group (SUDO_USER not set)"
        log_error "You may need to manually run: sudo usermod -aG docker YOUR_USERNAME"
        return 1
    fi

    log_info "Adding user '$target_user' to docker group..."

    if groups "$target_user" | grep -q '\bdocker\b'; then
        log_info "User '$target_user' already in docker group"
    else
        usermod -aG docker "$target_user"
        log_info "User '$target_user' added to docker group"
        log_info "Note: User needs to log out and back in for group changes to take effect"
    fi
}

deploy_portainer() {
    log_info "Deploying Portainer CE..."

    # Get script directory to locate configs directory
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local compose_file="${script_dir}/../configs/docker-compose.yml"

    if [[ ! -f "$compose_file" ]]; then
        log_error "Docker Compose file not found at: $compose_file"
        return 1
    fi

    # Stop and remove existing Portainer containers if present
    if docker ps -a | grep -q portainer; then
        log_info "Stopping existing Portainer containers..."
        docker compose -f "$compose_file" down || true
    fi

    # Deploy Portainer
    log_info "Starting Portainer using docker compose..."
    docker compose -f "$compose_file" up -d

    log_info "Portainer deployed successfully"
}

verify_docker() {
    log_info "Verifying Docker installation..."

    if docker run --rm hello-world &>/dev/null; then
        log_info "Docker verification successful"
        return 0
    else
        log_error "Docker verification failed"
        return 1
    fi
}

print_access_info() {
    cat << 'EOF'

==========================================================
Docker + Portainer installation completed successfully
==========================================================

Docker Engine is now running and enabled at boot.

Portainer CE is accessible at:
  https://localhost:9443

NEXT STEPS:
1. If you were added to the docker group, log out and back in
   to use docker without sudo
2. Access Portainer at https://localhost:9443
3. Create your admin account on first visit
4. Test Docker with: docker run hello-world

NOTES:
- Portainer data is stored in the portainer_data volume
- To manage Portainer: docker compose -f configs/docker-compose.yml [up|down|logs]

==========================================================
EOF
}

main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    log_info "Starting Docker Engine + Portainer installation"

    remove_old_docker
    add_docker_repository
    install_docker
    configure_docker_service
    add_user_to_docker_group || true
    deploy_portainer
    verify_docker
    print_access_info

    log_info "Docker + Portainer installation completed"
}

main "$@"
