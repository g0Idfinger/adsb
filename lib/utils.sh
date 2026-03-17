#!/usr/bin/env bash
# lib/utils.sh — Common library for logging, error traps, and string validation.

# --- Guard ---
[[ -n "${_UTILS_SH_SOURCED:-}" ]] && return 0
_UTILS_SH_SOURCED=1

# --- Strict Mode ---
set -Eeuo pipefail

# --- Constants ---
# shellcheck disable=SC2034
readonly LOG_COLORS_DEBUG="\033[0;36m"
# shellcheck disable=SC2034
readonly LOG_COLORS_INFO="\033[0;32m"
# shellcheck disable=SC2034
readonly LOG_COLORS_WARN="\033[0;33m"
# shellcheck disable=SC2034
readonly LOG_COLORS_ERROR="\033[0;31m"
readonly LOG_COLORS_RESET="\033[0m"

# --- Functions ---

# log(level, message)
log() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local timestamp
    timestamp="$(date +'%Y-%m-%d %H:%M:%S')"

    # Check if we should use colors (only if STDERR is a TTY)
    if [[ -t 2 ]]; then
        local color_var="LOG_COLORS_${level}"
        local color="${!color_var:-$LOG_COLORS_RESET}"
        printf "${color}[%s] %s: %s${LOG_COLORS_RESET}\n" "$timestamp" "$level" "$message" >&2
    else
        printf "[%s] %s: %s\n" "$timestamp" "$level" "$message" >&2
    fi
}

info()  { log INFO  "$*"; }
warn()  { log WARN  "$*"; }
error() { log ERROR "$*"; }
debug() { if [[ "${_ADSB_VERBOSE:-false}" == "true" ]]; then log DEBUG "$*"; fi; }

# confirm(message)
# Returns 0 if user answers Y/y (or _ADSB_YES=true), 1 otherwise.
confirm() {
    local prompt="${1:-Continue?}"
    local choice
    
    if [[ "${_ADSB_YES:-false}" == "true" ]]; then
        return 0
    fi
    
    read -p "$prompt [y/N]: " -r choice
    case "$choice" in
        [yY]*) return 0 ;;
        *) return 1 ;;
    esac
}

# error_trap(code, line)
# --- Security ---
mask_credential() {
    local val="$1"
    if [[ ${#val} -le 6 ]]; then
        echo "***"
    else
        echo "${val:0:3}...${val: -3}"
    fi
}

redact_sensitive() {
    local input="$1"
    # Registry of sensitive patterns from Shard 04
    local -a patterns=(
        '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})' # FA UUID
        '([a-fA-F0-9]{32})'        # FA Hex
        '([a-zA-Z0-9]{16})'        # FR24
        # Note: Station IDs are less sensitive but we could mask them if needed
    )
    
    local output="$input"
    for pattern in "${patterns[@]}"; do
        # Use sed for global replacement within the string
        # We replace the captured group with ********
        # This is a bit tricky in pure bash with groups, so sed is safer
        output=$(echo "$output" | sed -E "s/$pattern/******** /g")
    done
    echo "$output"
}

error_trap() {
    local exit_code="$1"
    local line_no="$2"
    error "Error on line $line_no (exit code: $exit_code)"
    
    # Release lock if it exists
    if [[ -f "/tmp/adsb-installer.lock" ]]; then
        rm -f "/tmp/adsb-installer.lock"
    fi
    
    exit "$exit_code"
}

# validate_string(input, regex)
validate_string() {
    local input="$1"
    local regex="$2"
    if [[ "$input" =~ $regex ]]; then
        return 0
    else
        return 1
    fi
}

# check_disk_space(path, min_kb)
check_disk_space() {
    local target_path="$1"
    local min_kb="$2"
    local available_kb
    
    available_kb=$(df -k "$target_path" | awk 'NR==2 {print $4}')
    if [[ "$available_kb" -lt "$min_kb" ]]; then
        return 1
    fi
    return 0
}

# redact_env(key, value)
redact_env() {
    local key="$1"
    local value="$2"
    case "$key" in
        INSTALLER_DIR|DOCKER_IMAGE_TAG|TIMEZONE)
            echo "$value"
            ;;
        *)
            echo "[REDACTED]"
            ;;
    esac
}
