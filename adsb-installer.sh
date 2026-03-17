#!/usr/bin/env bash
# adsb-installer.sh — Main orchestrator for ADS-B Automated Installer.

# --- Strict Mode ---
set -Eeuo pipefail
trap 'error_trap $? $LINENO' ERR

# --- Constants ---
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
readonly LIB_DIR="${SCRIPT_DIR}/lib"
readonly VERSION="1.0.0"
readonly LOCKFILE="${_ADSB_LOCKFILE:-/tmp/adsb-installer.lock}"

# --- Source Library ---
# shellcheck disable=SC1091
if [[ -f "${LIB_DIR}/utils.sh" ]]; then
    source "${LIB_DIR}/utils.sh"
else
    echo "ERROR: Missing utility library at ${LIB_DIR}/utils.sh" >&2
    exit 10
fi

# shellcheck disable=SC1091
if [[ -f "${LIB_DIR}/os-config.sh" ]]; then
    source "${LIB_DIR}/os-config.sh"
else
    error "Missing OS config library at ${LIB_DIR}/os-config.sh"
    exit 10
fi

# shellcheck disable=SC1091
if [[ -f "${LIB_DIR}/docker-logic.sh" ]]; then
    source "${LIB_DIR}/docker-logic.sh"
else
    error "Missing Docker logic library at ${LIB_DIR}/docker-logic.sh"
    exit 10
fi

# shellcheck disable=SC1091
if [[ -f "${LIB_DIR}/state-manager.sh" ]]; then
    source "${LIB_DIR}/state-manager.sh"
else
    error "Missing State management library at ${LIB_DIR}/state-manager.sh"
    exit 10
fi

# shellcheck disable=SC1091
if [[ -f "${LIB_DIR}/wizard-ui.sh" ]]; then
    source "${LIB_DIR}/wizard-ui.sh"
else
    error "Missing Wizard UI library at ${LIB_DIR}/wizard-ui.sh"
    exit 10
fi

# shellcheck disable=SC1091
if [[ -f "${LIB_DIR}/dependency-manager.sh" ]]; then
    source "${LIB_DIR}/dependency-manager.sh"
else
    error "Missing Dependency Manager library at ${LIB_DIR}/dependency-manager.sh"
    exit 10
fi

# --- Defaults ---
_ADSB_VERBOSE=false
_ADSB_DRY_RUN=false
_ADSB_YES=false
_ADSB_CONFIG_ONLY=false
_ADSB_OP="DEPLOY"

# --- UX Constants ---
readonly COLOR_BOLD_CYAN="\033[1;36m"
readonly COLOR_RESET="\033[0m"

# --- UI Components ---
draw_header() {
    local text="$1"
    local term_width
    term_width=$(tput cols 2>/dev/null || echo 80)
    
    echo -e "\n${COLOR_BOLD_CYAN}$(printf '═%.0s' $(seq 1 "$term_width"))${COLOR_RESET}"
    echo -e "${COLOR_BOLD_CYAN}  $text${COLOR_RESET}"
    echo -e "${COLOR_BOLD_CYAN}$(printf '═%.0s' $(seq 1 "$term_width"))${COLOR_RESET}\n"
}

draw_progress() {
    local percent="$1"
    local label="${2:-Progress}"
    local term_width
    term_width=$(tput cols 2>/dev/null || echo 80)
    local bar_width=$(( term_width - 25 ))
    local filled=$(( percent * bar_width / 100 ))
    local empty=$(( bar_width - filled ))
    
    printf "\r  %-15s [%s%s] %3d%%" "$label" "$(printf '#%.0s' "$(seq 1 "$filled" 2>/dev/null || echo "")")" "$(printf ' %.0s' "$(seq 1 "$empty" 2>/dev/null || echo "")")" "$percent"
    if [[ "$percent" -eq 100 ]]; then echo ""; fi
}

# --- Usage ---
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Automated Bash-based installer and configurator for SDR-Enthusiasts ADS-B Docker stack.

Options:
    -h, --help          Show this help message
    -d, --dry-run       Preview changes without executing
    --diag              Generate a redacted diagnostic dump
    --restore           Restore .env from the most recent backup
    -v, --verbose       Enable verbose/debug output
    --version           Show version

Examples:
    $SCRIPT_NAME --dry-run
    $SCRIPT_NAME --verbose
EOF
    exit "${1:-0}"
}

# --- Argument Parsing ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)     usage 0 ;;
            -d|--dry-run)  _ADSB_DRY_RUN=true; shift ;;
            --diag)        _ADSB_OP="DIAG"; shift ;;
            --restore)     _ADSB_OP="RESTORE"; shift ;;
            -v|--verbose)  _ADSB_VERBOSE=true; shift ;;
            --version)     echo "$SCRIPT_NAME $VERSION"; exit 0 ;;
            --config-only) _ADSB_CONFIG_ONLY=true; shift ;;
            --yes|-y)      _ADSB_YES=true; shift ;;
            --)            shift; break ;;
            -*)            error "Unknown option: $1"; usage 1 ;;
            *)             break ;;
        esac
    done
}

# --- Pre-flight Checks ---
preflight() {
    # 1. Acquire Lock
    if [[ -f "$LOCKFILE" ]]; then
        error "Another instance is already running (Lockfile: $LOCKFILE exists)"
        exit 1
    fi
    touch "$LOCKFILE"
    trap 'rm -f "$LOCKFILE"' EXIT

    # 2. Resolve dependencies
    resolve_dependencies || exit 10
    
    # 3. Check for absolute path in INSTALLER_DIR if set
    if [[ -n "${INSTALLER_DIR:-}" ]]; then
        if [[ ! "$INSTALLER_DIR" =~ ^/ ]]; then
            error "INSTALLER_DIR must be an absolute path: $INSTALLER_DIR"
            exit 30
        fi
        
        # Restricted path check
        case "$INSTALLER_DIR" in
            /etc*|/bin*|/sbin*|/lib*|/usr*|/boot*)
                error "INSTALLER_DIR cannot be a system restricted directory: $INSTALLER_DIR"
                exit 30
                ;;
        esac
    fi

    # 4. Hardware and OS Verification
    probe_hardware || exit 10
    manage_os_config || exit 10
}

# --- Main ---
main() {
    parse_args "$@"
    
    draw_header "ADS-B INSTALLER v$VERSION"
    
    # Load existing config if available
    load_config

    # Initial status if dry run
    if [[ "$_ADSB_DRY_RUN" == true ]]; then
        info "[DRY RUN] mode enabled. No changes will be applied."
    fi

    preflight
    
    # Run Wizard unless it's a specific sub-operation that doesn't need it
    if [[ "$_ADSB_OP" == "DEPLOY" ]]; then
        run_wizard
    fi

    if [[ "$_ADSB_CONFIG_ONLY" == true ]]; then
        info "Configuration complete. Skipping deployment as requested."
        exit 0
    fi
    
    # Branch based on operation
    case "${_ADSB_OP:-DEPLOY}" in
        DIAG)
            draw_header "DIAGNOSTICS"
            info "Running diagnostics..."
            # Placeholder for future diag logic
            ;;
        RESTORE)
            draw_header "RESTORE CONFIG"
            if restore_config; then
                info "Successfully restored .env from backup."
                exit 0
            else
                error "Restore failed."
                exit 1
            fi
            ;;
        DEPLOY)
            draw_header "DEPLOYMENT FOUNDATION"
            info "Starting baseline deployment..."
            # For Slice 3, we simulate progress and call real deployment
            draw_progress 10 "Initializing"
            sleep 0.1
            draw_progress 30 "Merging Templates"
            sleep 0.1
            draw_progress 60 "Pulling Images"
            
            if deploy_stack; then
                draw_progress 100 "Done!"
                info "Baseline deployment successful."
            else
                error "Deployment failed."
                exit 20
            fi
            ;;
    esac

    info "Operation completed successfully."
}

# Only run if not being sourced (for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
