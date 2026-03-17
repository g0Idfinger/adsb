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
    for cmd in docker modprobe curl timedatectl; do
        touch "$FAKE_BIN/$cmd"
        chmod +x "$FAKE_BIN/$cmd"
    done
    
    # lsusb mock
    echo "echo 'Bus 001 Device 002: ID 0bda:2838 Realtek Semiconductor Corp. RTL2838 DVB-T'" > "$FAKE_BIN/lsusb"
    chmod +x "$FAKE_BIN/lsusb"

    # Set installer dir for isolation
    export INSTALLER_DIR="$TMP_DIR/adsb-maint"
    mkdir -p "$INSTALLER_DIR"
    
    # Unique lockfile per test
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    export _ADSB_SKIP_DEPS=true
    
    # Source libraries
    source "${LIB_DIR}/utils.sh"
    source "${LIB_DIR}/state-manager.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "maintenance: safe_write_env creates automatic backups" {
    # Initialize .env
    echo 'LAT="52.34"' > "$INSTALLER_DIR/.env"
    
    # Trigger change
    safe_write_env "LAT" "53.00"
    
    # Check if backup directory exists and has a file
    [ -d "$INSTALLER_DIR/.backups" ]
    [ "$(ls -1 "$INSTALLER_DIR/.backups" | wc -l)" -eq 1 ]
}

@test "maintenance: restore flag picks most recent backup" {
    mkdir -p "$INSTALLER_DIR/.backups"
    echo 'LAT="40.00"' > "$INSTALLER_DIR/.backups/env.20260316_120000"
    sleep 1
    echo 'LAT="50.00"' > "$INSTALLER_DIR/.backups/env.20260316_130000"
    
    run "$INSTALLER_PATH" --restore
    
    [ "$status" -eq 0 ]
    grep -q 'LAT="50.00"' "$INSTALLER_DIR/.env"
}

@test "maintenance: restore fails if no backups exist" {
    rm -rf "$INSTALLER_DIR/.backups"
    
    run "$INSTALLER_PATH" --restore
    
    [ "$status" -eq 1 ]
    [[ "$output" == *"No backups found"* ]]
}

@test "maintenance: backup rotation keeps at most 5 files" {
    mkdir -p "$INSTALLER_DIR/.backups"
    for i in {1..10}; do
        # Use a pattern that matches env.*
        touch "$INSTALLER_DIR/.backups/env.20260316_00000$i"
        sleep 0.1
    done
    
    # Initial .env
    echo 'TEST="VAL"' > "$INSTALLER_DIR/.env"
    
    # This should trigger rotation
    safe_write_env "TEST" "VAL2"
    
    # Check count
    [ "$(ls -1 "$INSTALLER_DIR/.backups" | wc -l)" -le 5 ]
}
