#!/usr/bin/env bash
# lib/os-config.sh — Logic for hardware detection and host machine configuration.

# --- Guard ---
[[ -n "${_OS_CONFIG_SH_SOURCED:-}" ]] && return 0
_OS_CONFIG_SH_SOURCED=1

# --- Strict Mode ---
set -Eeuo pipefail

# --- Constants ---
readonly UDEV_RULES_FILE="${UDEV_RULES_PATH:-/etc/udev/rules.d/rtl-sdr.rules}"
readonly BLACKLIST_FILE="${BLACKLIST_PATH:-/etc/modprobe.d/exclusions-rtl2832.conf}"
readonly REPROBE_LOCK_FILE="/tmp/adsb-reprobe.time"

# --- Hardware Detection ---
probe_hardware() {
    info "Probing for RTL-SDR hardware..."
    
    local lsusb_out
    lsusb_out=$(lsusb 2>/dev/null || true)
    
    if [[ -z "$lsusb_out" ]]; then
        error "lsusb failed or is not available."
        return 10
    fi
    
    if echo "$lsusb_out" | grep -q "0bda:2832" || echo "$lsusb_out" | grep -q "0bda:2838"; then
        info "Found RTL-SDR hardware (0bda:2832/2838)."
        return 0
    else
        error "No RTL-SDR hardware detected. Ensure it is plugged in."
        return 10
    fi
}

# --- Udev & Modprobe ---
manage_os_config() {
    info "Verifying OS configuration..."
    
    # 1. Symlink Protection
    if [[ -L "$UDEV_RULES_FILE" ]]; then
        error "Target udev rules file is a symbolic link: $UDEV_RULES_FILE. Aborting for security."
        return 10
    fi
    
    # 2. Check Docker Socket
    local socket_path="${DOCKER_SOCKET:-/var/run/docker.sock}"
    if [[ -S "$socket_path" ]]; then
        if [[ ! -w "$socket_path" ]]; then
            warn "Current user does not have write permissions on $socket_path."
            if confirm "Would you like to fix permissions on the Docker socket? (Requires sudo)"; then
                # Check for sudo
                local SUDO=""
                if [[ $EUID -ne 0 ]]; then
                    if ! command -v sudo &>/dev/null; then
                        error "Sudo required but not available."
                        return 10
                    fi
                    SUDO="sudo"
                fi
                $SUDO chmod 666 "$socket_path" || {
                    error "Failed to fix permissions on $socket_path."
                    return 10
                }
                info "Docker socket permissions fixed."
            else
                info "Consider running: sudo usermod -aG docker $USER"
                warn "Ignoring and proceeding, but deployment may fail."
            fi
        fi
    fi

    # 3. Kernel Module Blacklisting
    blacklist_kernel_modules || return 10
}

# --- Kernel Blacklisting ---
blacklist_kernel_modules() {
    # Check if already blacklisted
    if [[ -f "$BLACKLIST_FILE" ]]; then
        info "Kernel modules already blacklisted at $BLACKLIST_FILE"
        return 0
    fi
    
    warn "RTL-SDR kernel modules (DVB-T) should be blacklisted for Docker usage."
    if ! confirm "Would you like to blacklist RTL-SDR kernel modules? (Requires sudo & reboot)"; then
        warn "Proceeding without blacklisting. Device may be busy."
        return 0
    fi
    
    # Check for sudo
    local SUDO=""
    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo &>/dev/null; then
            error "Sudo required for blacklisting."
            return 10
        fi
        SUDO="sudo"
    fi
    
    info "Creating $BLACKLIST_FILE..."
    $SUDO tee "$BLACKLIST_FILE" > /dev/null <<EOF
# Blacklist host from loading modules for RTL-SDRs to ensure they
# are left available for the Docker guest.
blacklist dvb_core
blacklist dvb_usb_rtl2832u
blacklist dvb_usb_rtl28xxu
blacklist dvb_usb_v2
blacklist r820t
blacklist rtl2830
blacklist rtl2832
blacklist rtl2832_sdr
blacklist rtl2838

# Prevent on-demand loading
install dvb_core /bin/false
install dvb_usb_rtl2832u /bin/false
install dvb_usb_rtl28xxu /bin/false
install dvb_usb_v2 /bin/false
install r820t /bin/false
install rtl2830 /bin/false
install rtl2832 /bin/false
install rtl2832_sdr /bin/false
install rtl2838 /bin/false
EOF

    info "Unloading modules..."
    local modules=(dvb_core dvb_usb_rtl2832u dvb_usb_rtl28xxu dvb_usb_v2 r820t rtl2830 rtl2832 rtl2832_sdr rtl2838)
    for mod in "${modules[@]}"; do
        $SUDO modprobe -r "$mod" 2>/dev/null || true
    done
    
    info "Rebuilding module dependency database..."
    $SUDO depmod -a || info "depmod failed, safe to ignore if system handles it"
    
    if command -v update-initramfs &>/dev/null; then
        info "Updating initramfs (this may take a minute)..."
        $SUDO update-initramfs -u || info "initramfs update failed, safe to ignore on some systems"
    fi
    
    info "Blacklisting complete. A reboot is recommended."
}

# --- SDR Reprobe ---
reprobe_sdr() {
    # Check throttle
    if [[ -f "$REPROBE_LOCK_FILE" ]]; then
        local last_run
        last_run=$(cat "$REPROBE_LOCK_FILE")
        local now
        now=$(date +%s)
        if (( now - last_run < 60 )); then
            error "Reprobe throttled. Wait $(( 60 - (now - last_run) ))s."
            return 1
        fi
    fi
    
    info "Reprobing RTL-SDR kernel modules..."
    # Placeholder for actual modprobe logic (requires sudo)
    # sudo modprobe -r dvb_usb_rtl28xxu || true
    # sudo modprobe dvb_usb_rtl28xxu
    
    date +%s > "$REPROBE_LOCK_FILE"
}
