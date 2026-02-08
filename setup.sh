#!/bin/bash
#
# Ubuntu MacBook Pro Setup - Main Orchestrator
# Runs all setup scripts in order with interactive prompts
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ubuntu-setup.log"

# Script definitions
declare -A SCRIPTS=(
    [01]="01-system-update.sh"
    [02]="02-system-tweaks.sh"
    [03]="03-macbook-drivers.sh"
    [04]="04-claude-code.sh"
    [05]="05-korean-input.sh"
    [06]="06-keyboard-remap.sh"
    [07]="07-docker.sh"
    [08]="08-ssh-firewall.sh"
)

declare -A NAMES=(
    [01]="System Update & Base Packages"
    [02]="System Tweaks"
    [03]="MacBook Drivers"
    [04]="Claude Code CLI"
    [05]="Korean Input"
    [06]="Keyboard Remapping"
    [07]="Docker & Portainer"
    [08]="SSH & Firewall"
)

declare -A DESCRIPTIONS=(
    [01]="Updates system, installs essential tools and kernel headers"
    [02]="Forces X11, disables lid suspend, sets timezone, creates swap"
    [03]="WiFi drivers, fan control, power management"
    [04]="Claude Code CLI tool installation"
    [05]="fcitx5 + Hangul input method"
    [06]="Toshy key remapping + Fn key configuration"
    [07]="Docker engine + Portainer web UI"
    [08]="SSH server + UFW firewall configuration"
)

declare -A WARNINGS=(
    [02]="Reboot required for changes to take effect"
    [03]="REBOOT RECOMMENDED after this step"
)

declare -A EXEC_TYPE=(
    [01]="root"
    [02]="root"
    [03]="root"
    [04]="user"
    [05]="root"
    [06]="dual"  # Special: runs twice (user + root)
    [07]="root"
    [08]="root"
)

# Result tracking
declare -A RESULTS=()
declare -A TIMINGS=()
SKIP_REST=false
AUTO_MODE=false
ONLY_SCRIPT=""
FROM_SCRIPT=""

#
# Helper functions
#

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════╗"
    echo "║  Ubuntu MacBook Pro Setup (v2)           ║"
    echo "║  2013 MacBook Pro → Home Server          ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: sudo ./setup.sh [OPTIONS]

Options:
  --auto              Skip all prompts, run everything automatically
  --only <name>       Run only one script (e.g., --only docker)
  --from <name>       Start from a specific script (skip earlier ones)
  --list              Print script list and exit
  -h, --help          Show this help message

Available script names:
  system-update, system-tweaks, macbook-drivers, claude-code,
  korean-input, keyboard-remap, docker, ssh-firewall

Examples:
  sudo ./setup.sh                           # Interactive mode
  sudo ./setup.sh --auto                    # Automatic mode
  sudo ./setup.sh --only docker             # Install only Docker
  sudo ./setup.sh --from claude-code        # Resume from step 4
EOF
}

print_script_list() {
    echo "Available scripts:"
    echo ""
    for i in 01 02 03 04 05 06 07 08; do
        local name="${NAMES[$i]}"
        local desc="${DESCRIPTIONS[$i]}"
        local file="${SCRIPTS[$i]}"
        echo -e "${BOLD}[$i/8] $name${NC}"
        echo "  File: $file"
        echo "  Desc: $desc"
        echo ""
    done
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run with sudo${NC}"
        echo "Usage: sudo ./setup.sh"
        exit 1
    fi

    if [[ -z "${SUDO_USER:-}" ]]; then
        echo -e "${RED}Error: SUDO_USER not set. Please run with sudo, not as root directly.${NC}"
        exit 1
    fi
}

name_to_number() {
    local name="$1"
    case "$name" in
        system-update) echo "01" ;;
        system-tweaks) echo "02" ;;
        macbook-drivers) echo "03" ;;
        claude-code) echo "04" ;;
        korean-input) echo "05" ;;
        keyboard-remap) echo "06" ;;
        docker) echo "07" ;;
        ssh-firewall) echo "08" ;;
        *) echo "" ;;
    esac
}

should_run_script() {
    local num="$1"

    # Check --only filter
    if [[ -n "$ONLY_SCRIPT" ]]; then
        [[ "$num" == "$ONLY_SCRIPT" ]] && return 0 || return 1
    fi

    # Check --from filter
    if [[ -n "$FROM_SCRIPT" ]]; then
        [[ "$((10#$num))" -ge "$((10#$FROM_SCRIPT))" ]] && return 0 || return 1
    fi

    return 0
}

prompt_execute() {
    local num="$1"
    local name="${NAMES[$num]}"
    local desc="${DESCRIPTIONS[$num]}"
    local warning="${WARNINGS[$num]:-}"

    echo ""
    echo -e "${BLUE}${BOLD}[$num/8] $name${NC}"
    echo -e "  ${CYAN}→${NC} $desc"

    if [[ -n "$warning" ]]; then
        echo -e "  ${YELLOW}⚠${NC}  $warning"
    fi

    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "  ${GREEN}Auto-executing...${NC}"
        return 0
    fi

    while true; do
        read -p "  Execute? [Y/n/s] " -n 1 -r
        echo
        case $REPLY in
            [Yy]|"") return 0 ;;
            [Nn]) return 1 ;;
            [Ss]) SKIP_REST=true; return 1 ;;
            *) echo "  Invalid input. Use Y/y (yes), N/n (skip), or S/s (skip all)" ;;
        esac
    done
}

execute_script() {
    local num="$1"
    local script="${SCRIPTS[$num]}"
    local script_path="$SCRIPT_DIR/scripts/$script"
    local exec_type="${EXEC_TYPE[$num]}"

    if [[ ! -f "$script_path" ]]; then
        echo -e "  ${RED}✗ Script not found: $script_path${NC}"
        RESULTS[$num]="FAILED"
        return 1
    fi

    local start_time
    start_time=$(date +%s)
    local result=0

    case "$exec_type" in
        user)
            # Run as regular user
            echo -e "  ${CYAN}Running as user: $SUDO_USER${NC}"
            if su - "$SUDO_USER" -c "bash '$script_path'" 2>&1 | tee -a "$LOG_FILE"; then
                result=0
            else
                result=$?
            fi
            ;;
        dual)
            # Run twice: first as user (Toshy), then as root (Fn key)
            echo -e "  ${CYAN}Phase 1: Running as user (Toshy installation)${NC}"
            if su - "$SUDO_USER" -c "bash '$script_path'" 2>&1 | tee -a "$LOG_FILE"; then
                echo -e "  ${CYAN}Phase 2: Running as root (Fn key configuration)${NC}"
                if bash "$script_path" 2>&1 | tee -a "$LOG_FILE"; then
                    result=0
                else
                    result=$?
                fi
            else
                result=$?
            fi
            ;;
        *)
            # Run as root
            if bash "$script_path" 2>&1 | tee -a "$LOG_FILE"; then
                result=0
            else
                result=$?
            fi
            ;;
    esac

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    TIMINGS[$num]=$elapsed

    if [[ $result -eq 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Completed ($(format_time $elapsed))"
        RESULTS[$num]="OK"
        return 0
    else
        echo -e "  ${RED}✗${NC} Failed ($(format_time $elapsed))"
        RESULTS[$num]="FAILED"
        return 1
    fi
}

format_time() {
    local seconds=$1
    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    else
        local minutes=$((seconds / 60))
        local secs=$((seconds % 60))
        echo "${minutes}m ${secs}s"
    fi
}

check_reboot_after_drivers() {
    if [[ "$AUTO_MODE" == true ]]; then
        echo -e "${YELLOW}Auto-mode: Skipping reboot prompt${NC}"
        return
    fi

    echo ""
    echo -e "${YELLOW}${BOLD}*** REBOOT RECOMMENDED ***${NC}"
    echo "WiFi drivers and X11 settings need a reboot to take effect."
    echo ""
    read -p "Reboot now? [Y/n] " -r

    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        echo ""
        echo -e "${CYAN}After reboot, resume with:${NC}"
        echo "  sudo ./setup.sh --from claude-code"
        echo ""
        sleep 2
        reboot
    else
        echo -e "${CYAN}Continuing without reboot...${NC}"
        echo -e "${YELLOW}Remember to reboot before using WiFi!${NC}"
    fi
}

print_summary() {
    local total_time=0
    local ok_count=0
    local failed_count=0
    local skipped_count=0

    echo ""
    echo -e "${CYAN}${BOLD}═══ Summary ═══════════════════════════════${NC}"

    for i in 01 02 03 04 05 06 07 08; do
        local name="${NAMES[$i]}"
        local result="${RESULTS[$i]:-SKIPPED}"
        local timing="${TIMINGS[$i]:-0}"
        total_time=$((total_time + timing))

        local status_icon=""
        local status_color=""

        case "$result" in
            OK)
                status_icon="✓"
                status_color="$GREEN"
                ok_count=$((ok_count + 1))
                ;;
            FAILED)
                status_icon="✗"
                status_color="$RED"
                failed_count=$((failed_count + 1))
                ;;
            SKIPPED)
                status_icon="-"
                status_color="$YELLOW"
                skipped_count=$((skipped_count + 1))
                ;;
        esac

        printf "  ${status_color}${status_icon}${NC} %-20s %-10s" "$name" "$result"
        if [[ $timing -gt 0 ]]; then
            printf "(%s)\n" "$(format_time "$timing")"
        else
            printf "\n"
        fi
    done

    echo ""
    echo -e "${BOLD}Total: $ok_count OK, $failed_count FAILED, $skipped_count SKIPPED ($(format_time $total_time))${NC}"
    echo ""

    # Check if reboot is needed
    local needs_reboot=false
    for num in 02 03; do
        if [[ "${RESULTS[$num]:-}" == "OK" ]]; then
            needs_reboot=true
            break
        fi
    done

    if [[ "$needs_reboot" == true ]]; then
        echo -e "${YELLOW}⚠  Reboot recommended to apply all changes.${NC}"
    fi

    echo -e "${CYAN}Run ./verify.sh after reboot to check installation.${NC}"
    echo ""
}

#
# Main execution
#

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --only)
                if [[ -z "${2:-}" ]]; then
                    echo -e "${RED}Error: --only requires a script name${NC}"
                    exit 1
                fi
                ONLY_SCRIPT=$(name_to_number "$2")
                if [[ -z "$ONLY_SCRIPT" ]]; then
                    echo -e "${RED}Error: Unknown script name: $2${NC}"
                    print_usage
                    exit 1
                fi
                shift 2
                ;;
            --from)
                if [[ -z "${2:-}" ]]; then
                    echo -e "${RED}Error: --from requires a script name${NC}"
                    exit 1
                fi
                FROM_SCRIPT=$(name_to_number "$2")
                if [[ -z "$FROM_SCRIPT" ]]; then
                    echo -e "${RED}Error: Unknown script name: $2${NC}"
                    print_usage
                    exit 1
                fi
                shift 2
                ;;
            --list)
                print_script_list
                exit 0
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}"
                print_usage
                exit 1
                ;;
        esac
    done

    check_root
    print_header

    # Initialize log
    echo "=== Ubuntu MacBook Setup - $(date) ===" | tee "$LOG_FILE"
    echo "User: $SUDO_USER" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    # Execute scripts
    for num in 01 02 03 04 05 06 07 08; do
        # Check if should run this script
        if ! should_run_script "$num"; then
            RESULTS[$num]="SKIPPED"
            continue
        fi

        # Check skip_rest flag
        if [[ "$SKIP_REST" == true ]]; then
            RESULTS[$num]="SKIPPED"
            continue
        fi

        # Prompt user
        if ! prompt_execute "$num"; then
            RESULTS[$num]="SKIPPED"
            continue
        fi

        # Execute script
        execute_script "$num"

        # Special handling after macbook-drivers
        if [[ "$num" == "03" ]] && [[ "${RESULTS[$num]}" == "OK" ]]; then
            check_reboot_after_drivers
        fi
    done

    # Print summary
    print_summary
}

# Run main
main "$@"
