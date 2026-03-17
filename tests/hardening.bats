#!/usr/bin/env bats

setup() {
    export TMP_DIR="$(mktemp -d)"
    export LIB_DIR="${BATS_TEST_DIRNAME}/../lib"
    
    # Mock info/error/warn
    info() { :; }
    error() { :; }
    warn() { :; }
    export -f info error warn
    export _ADSB_SKIP_DEPS=true
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    
    source "${LIB_DIR}/utils.sh"
    source "${LIB_DIR}/docker-logic.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "hardening: redact_sensitive hides FlightAware keys" {
    local raw="Configuring FlightAware with key abcdef0123456789abcdef0123456789 for user"
    local redacted
    redacted=$(redact_sensitive "$raw")
    
    [[ "$redacted" != *"abcdef0123456789abcdef0123456789"* ]]
    [[ "$redacted" == *"********"* ]]
}

@test "hardening: redact_sensitive hides FlightAware UUID keys" {
    local raw="Configuring FlightAware with key 4dbf13ed-7a22-404d-8a90-eee250ebe68a for user"
    local redacted
    redacted=$(redact_sensitive "$raw")
    
    [[ "$redacted" != *"4dbf13ed-7a22-404d-8a90-eee250ebe68a"* ]]
    [[ "$redacted" == *"********"* ]]
}

@test "hardening: redact_sensitive hides FR24 keys" {
    local raw="FR24 Key: 1234567890abcdef"
    local redacted
    redacted=$(redact_sensitive "$raw")
    
    [[ "$redacted" != *"1234567890abcdef"* ]]
    [[ "$redacted" == *"********"* ]]
}

@test "hardening: redact_sensitive preserves non-sensitive content" {
    local raw="Starting ultrafeeder on port 30005"
    local redacted
    redacted=$(redact_sensitive "$raw")
    
    [[ "$redacted" == "Starting ultrafeeder on port 30005" ]]
}

@test "health: check_feeder_logs detects connection success" {
    docker() {
        if [[ "$*" == "logs fa"* ]]; then
            echo "2026-03-16 12:00:00 [info] Beast input connected to localhost:30005"
            return 0
        fi
        return 1
    }
    export -f docker
    
    run check_feeder_logs "fa"
    [ "$status" -eq 0 ]
}

@test "health: check_feeder_logs detects auth failure" {
    docker() {
        if [[ "$*" == "logs fa"* ]]; then
            echo "2026-03-16 12:00:00 [error] Invalid key provided. Authentication failed."
            return 0
        fi
        return 1
    }
    export -f docker
    
    run check_feeder_logs "fa"
    [ "$status" -eq 1 ]
}

@test "health: check_health_once verifies graphs port when enabled" {
    export ENABLE_GRAPHS=true
    
    # Mock docker compose ps (minimal healthy)
    docker() {
        if [[ "$*" == "compose version" ]]; then
            return 0
        fi
        if [[ "$*" == "compose ps --format json" ]]; then
            echo '{"Service": "base", "Status": "running"}'
            return 0
        fi
        return 1
    }
    export -f docker
    
    # Mock curl
    curl() {
        if [[ "$*" == *":8081"* ]]; then
            return 0 # Graphs healthy
        fi
        if [[ "$*" == *":8080"* ]]; then
            return 0 # Base healthy
        fi
        return 1
    }
    export -f curl
    
    run check_health_once
    [ "$status" -eq 0 ]
}
