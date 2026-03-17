#!/usr/bin/env bats

setup() {
    export TMP_DIR="$(mktemp -d)"
    export INSTALLER_PATH="${BATS_TEST_DIRNAME}/../adsb-installer.sh"
    export LIB_DIR="${BATS_TEST_DIRNAME}/../lib"
    
    # Create fake bin dir
    export FAKE_BIN="$TMP_DIR/bin"
    mkdir -p "$FAKE_BIN"
    export PATH="$FAKE_BIN:$PATH"
    
    # Set installer dir for isolation
    export INSTALLER_DIR="$TMP_DIR/adsb-state"
    mkdir -p "$INSTALLER_DIR"
    
    # Unique lockfile per test
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    
    # Source the library under test
    # Note: we source it here but tests will run it via the orchestrator or directly
    if [[ -f "${LIB_DIR}/state-manager.sh" ]]; then
        source "${LIB_DIR}/state-manager.sh"
    fi
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "persistence: safe_write_env writes to .env with 600 permissions" {
    # This will fail because safe_write_env isn't implemented yet
    run bash -c "source ${LIB_DIR}/utils.sh && source ${LIB_DIR}/state-manager.sh && safe_write_env TEST_KEY TEST_VALUE"
    
    [ -f "$INSTALLER_DIR/.env" ]
    [ "$(stat -c '%a' "$INSTALLER_DIR/.env")" -eq 600 ]
    grep -q 'TEST_KEY="TEST_VALUE"' "$INSTALLER_DIR/.env"
}

@test "persistence: safe_write_env rejects values with newlines" {
    run bash -c "source ${LIB_DIR}/utils.sh && source ${LIB_DIR}/state-manager.sh && safe_write_env TEST_KEY \$'val\nue'"
    [ "$status" -eq 30 ]
}

@test "persistence: safe_write_env creates a backup before mutation" {
    mkdir -p "$INSTALLER_DIR/.backups"
    echo 'OLD_KEY="OLD_VAL"' > "$INSTALLER_DIR/.env"
    
    run bash -c "source ${LIB_DIR}/utils.sh && source ${LIB_DIR}/state-manager.sh && safe_write_env NEW_KEY NEW_VAL"
    
    # Check if backup exists
    [ -n "$(ls -A "$INSTALLER_DIR/.backups")" ]
}

@test "validation: coordinates reject out-of-range values" {
    # Test Lat validation via direct call or wizard mock
    run bash -c "source ${LIB_DIR}/utils.sh && source ${LIB_DIR}/state-manager.sh && validate_coordinate LAT 95"
    [ "$status" -eq 30 ]
    
    run bash -c "source ${LIB_DIR}/utils.sh && source ${LIB_DIR}/state-manager.sh && validate_coordinate LAT -90.1"
    [ "$status" -eq 30 ]
}

@test "validation: coordinates accept valid values" {
    run bash -c "source ${LIB_DIR}/utils.sh && source ${LIB_DIR}/state-manager.sh && validate_coordinate LAT 52.34"
    [ "$status" -eq 0 ]
}
