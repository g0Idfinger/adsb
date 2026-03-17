#!/usr/bin/env bats

setup() {
    export TMP_DIR="$(mktemp -d)"
    export LIB_DIR="${BATS_TEST_DIRNAME}/../lib"
    
    # Mock info/error/warn/confirm
    info() { echo "INFO: $*"; }
    error() { echo "ERROR: $*"; }
    warn() { echo "WARN: $*"; }
    confirm() { return 0; } # Always auto-confirm for tests
    export -f info error warn confirm
    
    # Defaults
    export _ADSB_YES=false
    export _ADSB_VERBOSE=false
    
    source "${LIB_DIR}/dependency-manager.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "deps: resolve_dependencies returns 0 if all found" {
    # Mock command -v to always succeed
    command() { return 0; }
    export -f command
    
    run resolve_dependencies
    [ "$status" -eq 0 ]
}

@test "deps: resolve_dependencies fails on non-Debian if missing" {
    # Mock command to fail for 'docker'
    command() {
        if [[ "$*" == "-v docker" ]]; then return 1; fi
        return 0
    }
    export -f command
    
    # Fake a non-Debian system (marker missing)
    export DEBIAN_MARKER="${TMP_DIR}/no_debian"
    
    run resolve_dependencies
    [ "$status" -eq 10 ]
}

@test "deps: install_missing uses apt-get on Debian" {
    # Mock debian_version
    export DEBIAN_MARKER="${TMP_DIR}/debian_version"
    touch "$DEBIAN_MARKER"
    
    # Mock apt-get and sudo to verify they are called
    apt-get() {
        echo "APT_CALLED: $*"
        return 0
    }
    sudo() {
        "$@"
    }
    export -f apt-get sudo
    
    run install_missing "lsusb" "docker" "docker-compose"
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"APT_CALLED: install -y -qq usbutils docker.io docker-compose"* ]]
}

@test "deps: resolve_dependencies honors _ADSB_YES" {
    command() { return 1; } # Everything missing
    export -f command
    
    # Mock confirm to fail, but _ADSB_YES=true should bypass it
    confirm() { return 1; }
    export -f confirm
    export _ADSB_YES=true
    
    # Mock exit on failure to avoid actually running apt-get
    install_missing() { return 0; }
    export -f install_missing
    
    run resolve_dependencies
    [ "$status" -eq 0 ]
}

@test "deps: resolve_dependencies detects docker compose v2 plugin" {
    # Mock command -v for everything except docker-compose
    command() {
        if [[ "$*" == "-v docker-compose" ]]; then return 1; fi
        return 0
    }
    # Mock docker compose version to succeed
    docker() {
        if [[ "$*" == "compose version" ]]; then return 0; fi
        return 1
    }
    export -f command docker
    
    run resolve_dependencies
    [ "$status" -eq 0 ]
}

@test "deps: resolve_dependencies identifies missing docker compose" {
    # Mock command to fail for docker-compose
    command() {
        if [[ "$*" == "-v docker-compose" ]]; then return 1; fi
        return 0
    }
    # Mock docker compose version to fail
    docker() {
        if [[ "$*" == "compose version" ]]; then return 1; fi
        return 0
    }
    export -f command docker
    
    # Fake a non-Debian system to trigger early exit for easier verification
    export DEBIAN_MARKER="${TMP_DIR}/no_debian"
    
    run resolve_dependencies
    echo "Output: $output"
    [ "$status" -eq 10 ]
    [[ "$output" == *"Missing dependencies: docker-compose"* ]]
}
