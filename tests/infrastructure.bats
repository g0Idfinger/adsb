#!/usr/bin/env bats

setup() {
    export TMP_DIR="$(mktemp -d)"
    export INSTALLER_PATH="${BATS_TEST_DIRNAME}/../adsb-installer.sh"
    # Create fake binaries to satisfy dependency checks
    mkdir -p "$TMP_DIR/bin"
    for cmd in docker sed grep mv awk timedatectl; do
        touch "$TMP_DIR/bin/$cmd"
        chmod +x "$TMP_DIR/bin/$cmd"
    done
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    export _ADSB_SKIP_DEPS=true
    export PATH="$TMP_DIR/bin:$PATH"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "help: --help should return 0 and show usage" {
    run "$INSTALLER_PATH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"--help"* ]]
}

@test "help: -h should return 0 and show usage" {
    run "$INSTALLER_PATH" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "dry-run: --dry-run should set dry run mode" {
    # We expect the script to log that it is in dry run mode
    run "$INSTALLER_PATH" --dry-run --yes
    # Even if it fails later due to missing config, we check for dry-run acknowledgment
    [[ "$output" == *"[DRY RUN]"* ]] || [[ "$output" == *"Dry run mode enabled"* ]]
}

@test "config: fails with Exit 30 if INSTALLER_DIR is relative" {
    export INSTALLER_DIR="relative/path"
    run "$INSTALLER_PATH" --yes
    [ "$status" -eq 30 ]
    [[ "$output" == *"must be an absolute path"* ]]
}

@test "config: fails with Exit 30 if INSTALLER_DIR is restricted (/etc)" {
    export INSTALLER_DIR="/etc"
    run "$INSTALLER_PATH" --yes
    [ "$status" -eq 30 ]
    [[ "$output" == *"restricted directory"* ]]
}

@test "lock: prevents parallel execution" {
    # Create a dummy lockfile
    touch "$_ADSB_LOCKFILE"
    run "$INSTALLER_PATH" --yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"Another instance is already running"* ]]
    rm -f "$_ADSB_LOCKFILE"
}

@test "logging: utils log format check" {
    # Source utils.sh
    source "${BATS_TEST_DIRNAME}/../lib/utils.sh"
    # Capture stderr as well
    run log INFO "Test Message"
    # Use a simpler regex check for the timestamp and level
    [[ "$output" == *"INFO: Test Message"* ]]
    [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}
