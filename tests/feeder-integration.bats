#!/usr/bin/env bats

setup() {
    export TMP_DIR="$(mktemp -d)"
    export INSTALLER_PATH="${BATS_TEST_DIRNAME}/../adsb-installer.sh"
    export LIB_DIR="${BATS_TEST_DIRNAME}/../lib"
    export _ADSB_SKIP_DEPS=true
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    
    # Create fake bin dir
    export FAKE_BIN="$TMP_DIR/bin"
    mkdir -p "$FAKE_BIN"
    export PATH="$FAKE_BIN:$PATH"
    
    # Mocks
    for cmd in docker modprobe curl; do
        touch "$FAKE_BIN/$cmd"
        chmod +x "$FAKE_BIN/$cmd"
    done
    
    # timedatectl mock
    echo "echo 'UTC'; echo 'Europe/Amsterdam'; echo 'America/New_York'" > "$FAKE_BIN/timedatectl"
    chmod +x "$FAKE_BIN/timedatectl"
    
    # lsusb mock
    echo "echo 'Bus 001 Device 002: ID 0bda:2838 Realtek Semiconductor Corp. RTL2838 DVB-T'" > "$FAKE_BIN/lsusb"
    chmod +x "$FAKE_BIN/lsusb"

    # Set installer dir for isolation
    export INSTALLER_DIR="$TMP_DIR/adsb-feeders"
    mkdir -p "$INSTALLER_DIR"
    
    # Unique lockfile per test
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    
    # Reset environment variables that might leak from other tests
    for var in LAT LON ALT FEEDER_LAT FEEDER_LONG FEEDER_ALT_M FEEDER_TZ TIMEZONE \
               ENABLE_FA ENABLE_FR24 ENABLE_PLANEWATCH ENABLE_RBFEEDER ENABLE_PFCLIENT \
               ENABLE_ADSBHUB ENABLE_OPENSKY ENABLE_AGGREGATORS ENABLE_GRAPHS; do
        unset "$var"
    done
    
    # Source libraries
    source "${LIB_DIR}/utils.sh"
    source "${LIB_DIR}/state-manager.sh"
    source "${LIB_DIR}/wizard-ui.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "feeders: selection prompts for keys and station IDs" {
    # 1. Welcome ([Enter])
    # 2. LAT, LON, ALT, TZ
    # 3. Feeder Select (1) -> FA
    # 4. Aggregator Group Toggle (y) -> All aggregators
    # 5. FA key
    run "$INSTALLER_PATH" --config-only <<EOF

52.34
4.89
10
UTC
1
y
abcdef0123456789abcdef0123456789
EOF

    [ "$status" -eq 0 ]
    grep -q 'PIAWARE_FEEDER_ID="abcdef0123456789abcdef0123456789"' "$INSTALLER_DIR/.env"
    grep -q 'ENABLE_AGGREGATORS="true"' "$INSTALLER_DIR/.env"
}

@test "feeders: assemble_compose generates correct ULTRAFEEDER_CONFIG" {
    # Set up environment
    export ENABLE_ADSBLOL=true
    export ENABLE_AIRPLANES=true
    
    # We need to source the logic to test the function directly or run a partial assembly
    source "${LIB_DIR}/docker-logic.sh"
    
    local config
    config=$(get_ultrafeeder_config)
    
    [[ "$config" == *"in.adsb.lol"* ]]
    [[ "$config" == *"feed.airplanes.live"* ]]
    
    # Test planewatch MLAT
    export ENABLE_PLANEWATCH=true
    config=$(get_ultrafeeder_config)
    [[ "$config" == *"mlat,planewatch,30105"* ]]
}

@test "utils: mask_credential redacts sensitive keys" {
    local fa_key="abcdef0123456789abcdef0123456789"
    local masked
    masked=$(mask_credential "$fa_key")
    
    [[ "$masked" == "abc...789" ]]
}
