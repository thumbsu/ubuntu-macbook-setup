#!/usr/bin/env bash

# Ubuntu 24.04 LTS Setup Script for 2013 MacBook Pro
# Main entry point for system configuration and installation
#
# Usage:
#   sudo ./setup.sh              - Run all setup scripts
#   sudo ./setup.sh --only NAME  - Run specific script
#   sudo ./setup.sh --from NAME  - Resume from a specific script
#   ./setup.sh --list            - List available scripts
#   ./setup.sh --help            - Show usage information

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
LOG_FILE="/var/log/ubuntu-setup.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script list in execution order
SCRIPTS=(
    "01-system-update"
    "02-macbook-drivers"
    "03-korean-input"
    "04-docker"
    "05-dev-tools"
    "06-ssh"
    "07-firewall"
    "08-system-tweaks"
    "09-keyboard-remap"
)

# Track execution results
declare -A RESULTS
TOTAL_START_TIME=$(date +%s)

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# Check for root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        echo "Usage: sudo $0"
        exit 1
    fi
}

# Initialize log file
init_log() {
    if [[ ! -f "${LOG_FILE}" ]]; then
        touch "${LOG_FILE}"
        chmod 644 "${LOG_FILE}"
    fi

    log "INFO" "============================================"
    log "INFO" "Ubuntu 24.04 Setup Script Started"
    log "INFO" "Timestamp: $(date)"
    log "INFO" "User: ${SUDO_USER:-root}"
    log "INFO" "============================================"
}

# List available scripts
list_scripts() {
    echo "Available setup scripts:"
    echo ""
    for script in "${SCRIPTS[@]}"; do
        local script_path="${SCRIPTS_DIR}/${script}.sh"
        if [[ -f "${script_path}" ]]; then
            echo -e "  ${GREEN}${script}${NC}"

            # Extract description from script if available
            local desc
            desc=$(grep -m1 "^# Description:" "${script_path}" 2>/dev/null | sed 's/# Description: //' || echo "")
            if [[ -n "${desc}" ]]; then
                echo "    ${desc}"
            fi
        else
            echo -e "  ${RED}${script}${NC} (not found)"
        fi
        echo ""
    done
}

# Show usage information
show_help() {
    cat << EOF
Usage: sudo $0 [OPTIONS]

Ubuntu 24.04 LTS setup script for 2013 MacBook Pro.
All scripts are idempotent and safe to re-run.

OPTIONS:
    --help              Show this help message
    --list              List all available scripts
    --only SCRIPT       Run only the specified script
                        (e.g., --only docker, --only 04-docker)
    --from SCRIPT       Resume from a specific script (runs it and all after)
                        (e.g., --from docker, --from 06-ssh)

EXAMPLES:
    sudo $0                      # Run all scripts in order
    sudo $0 --only docker        # Run only docker installation
    sudo $0 --only 04-docker     # Same as above
    sudo $0 --from ssh           # Resume from SSH script onwards
    $0 --list                    # List available scripts (no sudo needed)

SCRIPTS (in execution order):
EOF

    for script in "${SCRIPTS[@]}"; do
        echo "    - ${script}"
    done

    echo ""
}

# Run a single script
run_script() {
    local script_name="$1"
    local script_path="${SCRIPTS_DIR}/${script_name}.sh"

    if [[ ! -f "${script_path}" ]]; then
        log_error "Script not found: ${script_name}"
        return 1
    fi

    if [[ ! -x "${script_path}" ]]; then
        log_warning "Making script executable: ${script_name}"
        chmod +x "${script_path}"
    fi

    log_info "Starting: ${script_name}"
    log_info "----------------------------------------"

    local start_time
    start_time=$(date +%s)

    if bash "${script_path}"; then
        local end_time
        end_time=$(date +%s)
        local elapsed=$((end_time - start_time))

        log_success "Completed: ${script_name} (${elapsed}s)"
        RESULTS["${script_name}"]="SUCCESS:${elapsed}"
        return 0
    else
        local end_time
        end_time=$(date +%s)
        local elapsed=$((end_time - start_time))

        log_error "Failed: ${script_name} (${elapsed}s)"
        RESULTS["${script_name}"]="FAILED:${elapsed}"
        return 1
    fi
}

# Run all scripts in order
run_all_scripts() {
    local failed=0

    for script in "${SCRIPTS[@]}"; do
        if ! run_script "${script}"; then
            failed=$((failed + 1))
            log_warning "Continuing with remaining scripts..."
        fi
        echo ""
    done

    return "${failed}"
}

# Run scripts starting from a specific one
run_from_script() {
    local start_script="$1"
    local failed=0
    local found=false

    for script in "${SCRIPTS[@]}"; do
        if [[ "${script}" == "${start_script}" ]]; then
            found=true
        fi

        if [[ "${found}" == true ]]; then
            if ! run_script "${script}"; then
                failed=$((failed + 1))
                log_warning "Continuing with remaining scripts..."
            fi
            echo ""
        fi
    done

    return "${failed}"
}

# Find script by partial name
find_script() {
    local query="$1"

    # First try exact match
    for script in "${SCRIPTS[@]}"; do
        if [[ "${script}" == "${query}" ]]; then
            echo "${script}"
            return 0
        fi
    done

    # Try without number prefix
    for script in "${SCRIPTS[@]}"; do
        local base_name
        base_name=$(echo "${script}" | sed 's/^[0-9]*-//')
        if [[ "${base_name}" == "${query}" ]]; then
            echo "${script}"
            return 0
        fi
    done

    # Try partial match
    for script in "${SCRIPTS[@]}"; do
        if [[ "${script}" == *"${query}"* ]]; then
            echo "${script}"
            return 0
        fi
    done

    return 1
}

# Print summary
print_summary() {
    local total_end_time
    total_end_time=$(date +%s)
    local total_elapsed=$((total_end_time - TOTAL_START_TIME))

    echo ""
    log_info "============================================"
    log_info "Setup Summary"
    log_info "============================================"

    local success_count=0
    local failed_count=0

    for script in "${SCRIPTS[@]}"; do
        if [[ -n "${RESULTS[${script}]:-}" ]]; then
            local result="${RESULTS[${script}]}"
            local status="${result%%:*}"
            local elapsed="${result##*:}"

            if [[ "${status}" == "SUCCESS" ]]; then
                echo -e "  ${GREEN}✓${NC} ${script} (${elapsed}s)"
                success_count=$((success_count + 1))
            else
                echo -e "  ${RED}✗${NC} ${script} (${elapsed}s)"
                failed_count=$((failed_count + 1))
            fi
        fi
    done

    echo ""
    log_info "Total: ${success_count} succeeded, ${failed_count} failed"
    log_info "Total time: ${total_elapsed}s"
    log_info "Log file: ${LOG_FILE}"
    log_info "============================================"

    if [[ ${failed_count} -gt 0 ]]; then
        log_warning "Some scripts failed. Check ${LOG_FILE} for details."
        return 1
    else
        log_success "All scripts completed successfully!"
        return 0
    fi
}

# Main function
main() {
    local only_script=""
    local from_script=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --list|-l)
                list_scripts
                exit 0
                ;;
            --only)
                if [[ $# -lt 2 ]]; then
                    log_error "--only requires a script name"
                    echo "Use --list to see available scripts"
                    exit 1
                fi
                only_script="$2"
                shift 2
                ;;
            --from)
                if [[ $# -lt 2 ]]; then
                    log_error "--from requires a script name"
                    echo "Use --list to see available scripts"
                    exit 1
                fi
                from_script="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Check root for execution modes
    check_root
    init_log

    # Execute based on mode
    if [[ -n "${only_script}" ]]; then
        # Single script mode
        local script_name
        if script_name=$(find_script "${only_script}"); then
            run_script "${script_name}"
            print_summary
        else
            log_error "Script not found: ${only_script}"
            echo ""
            echo "Use --list to see available scripts"
            exit 1
        fi
    elif [[ -n "${from_script}" ]]; then
        # Resume from specific script
        local script_name
        if script_name=$(find_script "${from_script}"); then
            log_info "Resuming from: ${script_name}"
            run_from_script "${script_name}"
            print_summary
        else
            log_error "Script not found: ${from_script}"
            echo ""
            echo "Use --list to see available scripts"
            exit 1
        fi
    else
        # Run all scripts
        run_all_scripts
        print_summary
    fi
}

# Execute main function
main "$@"
