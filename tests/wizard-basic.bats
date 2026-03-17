#!/usr/bin/env bats

setup() {
    export TMP_DIR="$(mktemp -d)"
    export INSTALLER_PATH="${BATS_TEST_DIRNAME}/../adsb-installer.sh"
    export LIB_DIR="${BATS_TEST_DIRNAME}/../lib"
    
    # Create fake bin dir
    export FAKE_BIN="$TMP_DIR/bin"
    mkdir -p "$FAKE_BIN"
    export PATH="$FAKE_BIN:$PATH"
    
    # Mocks
    for cmd in docker modprobe curl; do
        touch "$FAKE_BIN/$cmd"
        chmod +x "$FAKE_BIN/$cmd"
    done
    
    echo "echo 'UTC'; echo 'Europe/Amsterdam'; echo 'America/New_York'" > "$FAKE_BIN/timedatectl"
    chmod +x "$FAKE_BIN/timedatectl"
    
    echo "echo 'Bus 001 Device 002: ID 0bda:2838 Realtek Semiconductor Corp. RTL2838 DVB-T'" > "$FAKE_BIN/lsusb"
    chmod +x "$FAKE_BIN/lsusb"

    # Set installer dir for isolation
    export INSTALLER_DIR="$TMP_DIR/adsb-wizard"
    mkdir -p "$INSTALLER_DIR"
    
    # Unique lockfile per test
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    export _ADSB_SKIP_DEPS=true
    
    # Reset environment variables that might leak from other tests
    for var in LAT LON ALT FEEDER_LAT FEEDER_LONG FEEDER_ALT_M FEEDER_TZ TIMEZONE \
               ENABLE_FA ENABLE_FR24 ENABLE_PLANEWATCH ENABLE_RBFEEDER ENABLE_PFCLIENT \
               ENABLE_ADSBHUB ENABLE_OPENSKY ENABLE_AGGREGATORS ENABLE_GRAPHS; do
        unset "$var"
    done
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "wizard: shows welcome splash on first run" {
    # Non-interactive, so it should exit at first prompt or finish if mocks allow
    run "$INSTALLER_PATH" --config-only <<< "n" 
    [[ "$output" == *"ADS-B INSTALLER"* ]]
}

@test "wizard: prompts for LAT and validates" {
    # Simulate user entering invalid then valid LAT
    # "\n" for welcome, then "invalid", then "52.34"
    run "$INSTALLER_PATH" --config-only <<EOF

95
52.34
0
0
UTC
EOF
    echo "Output: $output"
    [[ "$output" == *"Invalid Latitude"* ]]
    grep -q 'FEEDER_LAT="52.34"' "$INSTALLER_DIR/.env"
}

@test "wizard: headless mode skips all prompts" {
    export FEEDER_LAT=51.5
    export FEEDER_LONG=-0.1
    export FEEDER_ALT_M=10
    export FEEDER_TZ=UTC
    
    run "$INSTALLER_PATH" --yes --config-only
    [ "$status" -eq 0 ]
    grep -q 'FEEDER_LAT="51.5"' "$INSTALLER_DIR/.env"
    [[ "$output" != *"Please enter"* ]]
}

@test "wizard: resumes from last successful stage" {
    mkdir -p "$INSTALLER_DIR"
    echo 'LAST_STAGE="10"' > "$INSTALLER_DIR/.installer_state"
    echo 'FEEDER_LAT="52.34"' >> "$INSTALLER_DIR/.env"
    echo 'FEEDER_LONG="4.89"' >> "$INSTALLER_DIR/.env"
    
    # Run with --yes to resume automatically and skip prompts
    export FEEDER_ALT_M=10
    export FEEDER_TZ=UTC
    run "$INSTALLER_PATH" --yes --config-only
    echo "Output: $output"
    [[ "$output" == *"Resuming"* ]]
    grep -q 'FEEDER_ALT_M="10"' "$INSTALLER_DIR/.env"
}

@test "wizard: quick path skips core config when stack deployed" {
    # 1. Mock ultrafeeder exists
    echo -e '#!/bin/bash\necho "ultrafeeder"; exit 0' > "$FAKE_BIN/docker"
    chmod +x "$FAKE_BIN/docker"
    
    # 2. Mock existing configuration
    echo 'FEEDER_LAT="52.34"' > "$INSTALLER_DIR/.env"
    echo 'FEEDER_LONG="4.89"' >> "$INSTALLER_DIR/.env"
    export FEEDER_LAT="52.34"
    export FEEDER_LONG="4.89"
    export FEEDER_TZ="UTC"

    # 3. Use Quick Path (Y)
    # Wizard starts -> Welcome (Enter) -> Quick Path (Y) -> Feeder Selection...
    run "$INSTALLER_PATH" --config-only <<EOF

Y

EOF
    echo "Output: $output"
    [[ "$output" == *"QUICK PATH"* ]]
    [[ "$output" == *"Jumping to feeder selection"* ]]
}

@test "wizard: quick path proceeds to core config when user declines" {
    # 1. Mock ultrafeeder exists
    echo -e '#!/bin/bash\necho "ultrafeeder"; exit 0' > "$FAKE_BIN/docker"
    chmod +x "$FAKE_BIN/docker"
    
    # 2. Mock existing configuration
    echo 'FEEDER_LAT="52.34"' > "$INSTALLER_DIR/.env"
    echo 'FEEDER_LONG="4.89"' >> "$INSTALLER_DIR/.env"
    export FEEDER_LAT="52.34"
    export FEEDER_LONG="4.89"
    export FEEDER_TZ="UTC"

    # 3. Decline Quick Path (N) -> Enter Core Config (Defaults)
    run "$INSTALLER_PATH" --config-only <<EOF

N
52.35
4.90
10
UTC
EOF
    echo "Output: $output"
    [[ "$output" == *"QUICK PATH"* ]]
    [[ "$output" == *"CORE CONFIGURATION"* ]]
    grep -q 'FEEDER_LAT="52.35"' "$INSTALLER_DIR/.env"
}
