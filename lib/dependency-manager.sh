#!/usr/bin/env bash
# lib/dependency-manager.sh — Logic for checking and installing system dependencies.

# --- Guard ---
[[ -n "${_DEPENDENCY_MANAGER_SH_SOURCED:-}" ]] && return 0
_DEPENDENCY_MANAGER_SH_SOURCED=1

# --- Strict Mode ---
set -Eeuo pipefail

# --- Constants ---
readonly DEPS_FILE_LIST=(docker docker-compose sed grep mv awk curl lsusb)
get_package_name() {
    local dep="$1"
    local -A pkg_map=(
        ["docker"]="docker.io"
        ["docker-compose"]="docker-compose-v2"
        ["lsusb"]="usbutils"
        ["curl"]="curl"
        ["sed"]="sed"
        ["grep"]="grep"
        ["mv"]="coreutils"
        ["awk"]="gawk"
    )
    echo "${pkg_map[$dep]:-$dep}"
}

# --- Dependency Resolution ---
resolve_dependencies() {
    if [[ "${_ADSB_SKIP_DEPS:-false}" == "true" ]]; then
        return 0
    fi
    info "Verifying system dependencies..."
    
    local missing_deps=()
    for dep in "${DEPS_FILE_LIST[@]}"; do
        if [[ "$dep" == "docker-compose" ]]; then
            # Special check for docker compose (v1 binary or v2 plugin)
            if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
                missing_deps+=("$dep")
            fi
        elif ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        info "All dependencies found."
        return 0
    fi
    
    warn "Missing dependencies: ${missing_deps[*]}"
    
    if [[ "${_ADSB_YES:-false}" == "false" ]]; then
        if ! confirm "Would you like to attempt auto-installation of missing dependencies?"; then
            error "Cannot proceed without required dependencies."
            return 10
        fi
    fi
    
    install_missing "${missing_deps[@]}"
}

install_missing() {
    local -a deps=("$@")
    local debian_marker="${DEBIAN_MARKER:-/etc/debian_version}"
    
    # 1. Check for Debian-based system
    if [[ ! -f "$debian_marker" ]]; then
        error "Auto-installation is only supported on Debian-based systems (Debian/Ubuntu/PiOS)."
        error "Please install missing packages manually: ${deps[*]}"
        return 10
    fi
    
    # 2. Check for root/sudo
    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo &>/dev/null; then
            error "Root privileges or 'sudo' required to install dependencies."
            return 10
        fi
        SUDO="sudo"
    else
        SUDO=""
    fi
    
    info "Updating package lists..."
    $SUDO apt-get update -qq || warn "apt-get update failed, attempting installation anyway."
    
    local -a pkgs=()
    for dep in "${deps[@]}"; do
        pkgs+=("$(get_package_name "$dep")")
    done
    
    info "Installing: ${pkgs[*]}..."
    $SUDO apt-get install -y -qq "${pkgs[@]}" || {
        error "Failed to install dependencies."
        return 10
    }
    
    info "Dependencies installed successfully."
}
