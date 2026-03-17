#!/usr/bin/env bash
# --- Guard ---
[[ -n "${_STATE_MANAGER_SH_SOURCED:-}" ]] && return 0
_STATE_MANAGER_SH_SOURCED=1

# --- Strict Mode ---
set -Eeuo pipefail

# --- Constants ---
readonly ENV_FILE="${INSTALLER_DIR:-.}/.env"
readonly BACKUP_DIR="${INSTALLER_DIR:-.}/.backups"
readonly STATE_FILE="${INSTALLER_DIR:-.}/.installer_state"

# --- Validation Logic ---
validate_coordinate() {
    local type="$1"  # "LAT" or "LON"
    local value="$2"
    
    local lat_regex='^-?([1-8]?[0-9](\.[0-9]+)?|90(\.0+)?)$'
    local lon_regex='^-?((1[0-7][0-9]|[1-9]?[0-9])(\.[0-9]+)?|180(\.0+)?)$'
    
    if [[ "$type" == "LAT" ]]; then
        if [[ ! "$value" =~ $lat_regex ]]; then
            error "Invalid Latitude: $value (Must be between -90 and 90)"
            return 30
        fi
    elif [[ "$type" == "LON" ]]; then
        if [[ ! "$value" =~ $lon_regex ]]; then
            error "Invalid Longitude: $value (Must be between -180 and 180)"
            return 30
        fi
    fi
    return 0
}

# --- Persistence Logic ---
update_state() {
    local key="$1"
    local value="$2"
    
    # shellcheck disable=SC2155
    local temp_state="${STATE_FILE}.tmp"
    
    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^${key}=" "$STATE_FILE" > "$temp_state" || true
    else
        : > "$temp_state"
    fi
    
    echo "${key}=\"${value}\"" >> "$temp_state"
    chmod 600 "$temp_state"
    mv "$temp_state" "$STATE_FILE"
}

backup_config() {
    if [[ ! -f "$ENV_FILE" ]]; then return 0; fi
    
    mkdir -p "$BACKUP_DIR"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    cp "$ENV_FILE" "${BACKUP_DIR}/env.${timestamp}"
    
    # Prune old backups (keep last 5)
    # Using find/sort for ShellCheck SC2012 compliance
    # shellcheck disable=SC2012
    ls -dt "${BACKUP_DIR}"/env.* 2>/dev/null | tail -n +6 | xargs -r rm
}

safe_write_env() {
    local key="$1"
    local value="$2"
    
    # Reject newlines in values
    if [[ "$value" == *$'\n'* ]]; then
        error "Invalid value for $key: contains newlines"
        return 30
    fi
    
    # Create backup first
    backup_config
    
    local temp_env="${ENV_FILE}.tmp"
    
    # Build new env content
    if [[ -f "$ENV_FILE" ]]; then
        # Use grep -v to remove the old key, then append the new one
        grep -v "^${key}=" "$ENV_FILE" > "$temp_env" || true
    else
        : > "$temp_env"
    fi
    
    echo "${key}=\"${value}\"" >> "$temp_env"
    
    chmod 600 "$temp_env"
    mv "$temp_env" "$ENV_FILE"
}

load_config() {
    if [[ -f "$ENV_FILE" ]]; then
        # Using a restricted source-like pattern to avoid execution risks
        # We only want KEY="VALUE" lines
        while IFS='=' read -r key value; do
            if [[ "$key" =~ ^[A-Z0-9_]+$ ]]; then
                # Strip quotes if present
                value="${value%\"}"
                value="${value#\"}"
                export "$key"="$value"
            fi
        done < "$ENV_FILE"
    fi
    migrate_legacy_vars
}

migrate_legacy_vars() {
    # TZ
    if [[ -n "${TIMEZONE:-}" && -z "${FEEDER_TZ:-}" ]]; then
        info "Migrating TIMEZONE to FEEDER_TZ..."
        export FEEDER_TZ="$TIMEZONE"
        safe_write_env "FEEDER_TZ" "$FEEDER_TZ"
    fi
    # FlightAware
    if [[ -n "${FLIGHTAWARE_KEY:-}" && -z "${PIAWARE_FEEDER_ID:-}" ]]; then
        info "Migrating FLIGHTAWARE_KEY to PIAWARE_FEEDER_ID..."
        export PIAWARE_FEEDER_ID="$FLIGHTAWARE_KEY"
        safe_write_env "PIAWARE_FEEDER_ID" "$PIAWARE_FEEDER_ID"
    fi
    # FR24
    if [[ -n "${FR24_KEY:-}" && -z "${FR24_SHARING_KEY:-}" ]]; then
        info "Migrating FR24_KEY to FR24_SHARING_KEY..."
        export FR24_SHARING_KEY="$FR24_KEY"
        safe_write_env "FR24_SHARING_KEY" "$FR24_SHARING_KEY"
    fi
    # Coordinates and Altitude
    if [[ -n "${LAT:-}" && -z "${FEEDER_LAT:-}" ]]; then
        info "Migrating LAT to FEEDER_LAT..."
        export FEEDER_LAT="$LAT"
        safe_write_env "FEEDER_LAT" "$FEEDER_LAT"
    fi
    if [[ -n "${LON:-}" && -z "${FEEDER_LONG:-}" ]]; then
        info "Migrating LON to FEEDER_LONG..."
        export FEEDER_LONG="$LON"
        safe_write_env "FEEDER_LONG" "$FEEDER_LONG"
    fi
    if [[ -n "${ALT:-}" && -z "${FEEDER_ALT_M:-}" ]]; then
        info "Migrating ALT to FEEDER_ALT_M..."
        export FEEDER_ALT_M="$ALT"
        safe_write_env "FEEDER_ALT_M" "$FEEDER_ALT_M"
    fi
}

restore_config() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "No backups found (Directory $BACKUP_DIR missing)"
        return 1
    fi
    
    # shellcheck disable=SC2012
    latest=$(ls -dt "${BACKUP_DIR}"/env.* 2>/dev/null | head -n 1)
    
    if [[ -z "$latest" ]]; then
        error "No backups found in $BACKUP_DIR"
        return 1
    fi
    
    info "Restoring configuration from $latest"
    cp "$latest" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}
