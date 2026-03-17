#!/usr/bin/env bats

setup() {
    export TMP_DIR="$(mktemp -d)"
    export INSTALLER_PATH="${BATS_TEST_DIRNAME}/../adsb-installer.sh"
    export _ADSB_SKIP_DEPS=true
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    
    # Create fake bin dir
    export FAKE_BIN="$TMP_DIR/bin"
    mkdir -p "$FAKE_BIN"
    export PATH="$FAKE_BIN:$PATH"
    
    # Mock system commands
    for cmd in docker lsusb modprobe timedatectl curl; do
        touch "$FAKE_BIN/$cmd"
        chmod +x "$FAKE_BIN/$cmd"
    done

    # Specialized docker mock for network ls
    echo -e '#!/bin/bash\nif [[ "$*" == "network ls"* ]]; then exit 0; fi\nexit 0' > "$FAKE_BIN/docker"
    chmod +x "$FAKE_BIN/docker"

    # Mock /proc/sys/kernel/random/uuid
    mkdir -p "$TMP_DIR/proc/sys/kernel/random"
    echo "550e8400-e29b-41d4-a716-446655440000" > "$TMP_DIR/proc/sys/kernel/random/uuid"
    
    # Wrap cat to intercept uuid request if needed
    echo -e "#!/bin/bash\nif [[ \"\$*\" == \"/proc/sys/kernel/random/uuid\" ]]; then cat \"$TMP_DIR/proc/sys/kernel/random/uuid\"; else /usr/bin/cat \"\$@\"; fi" > "$FAKE_BIN/cat"
    chmod +x "$FAKE_BIN/cat"

    # Mock lsusb to pass hardware probe
    echo "Bus 001 Device 004: ID 0bda:2832 Realtek Semiconductor Corp. RTL2832U DVB-T" > "$TMP_DIR/lsusb_output"
    echo -e "#!/bin/bash\n/usr/bin/cat '$TMP_DIR/lsusb_output'" > "$FAKE_BIN/lsusb"
    chmod +x "$FAKE_BIN/lsusb"

    # Set installer dir for isolation
    export INSTALLER_DIR="$TMP_DIR/adsb-docker"
    mkdir -p "$INSTALLER_DIR/templates"
    cp "${BATS_TEST_DIRNAME}/../templates/base.yml" "$INSTALLER_DIR/templates/" 2>/dev/null || touch "$INSTALLER_DIR/templates/base.yml"
    cp "${BATS_TEST_DIRNAME}/../templates/networks.yml" "$INSTALLER_DIR/templates/" 2>/dev/null || touch "$INSTALLER_DIR/templates/networks.yml"

    # Unique lockfile per test
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    
    # Default coords and fast timeout for headless runs
    export LAT=52.34 LON=4.89 ALT=10 FEEDER_TZ=UTC
    export HEALTH_TIMEOUT=1
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "deployment: merges templates into INSTALLER_DIR/docker-compose.yml" {
    # Mock docker compose config to pass
    echo -e '#!/bin/bash\nexit 0' > "$FAKE_BIN/docker"
    chmod +x "$FAKE_BIN/docker"

    run "$INSTALLER_PATH" --dry-run --yes
    [ -f "$INSTALLER_DIR/docker-compose.yml" ]
}

@test "deployment: fails with Exit 20 if docker compose pull fails" {
    # Mock docker compose pull failure
    echo -e '#!/bin/bash\nif [[ "$*" == *"compose pull"* ]]; then exit 1; fi\nexit 0' > "$FAKE_BIN/docker"
    chmod +x "$FAKE_BIN/docker"

    run "$INSTALLER_PATH" --yes
    echo "Output: $output"
    [ "$status" -eq 20 ]
    [[ "$output" == *"docker compose pull failed"* ]]
}

@test "deployment: tracks progress with ProgressBar (simulated)" {
    # Mock docker commands
    echo -e '#!/bin/bash\nexit 0' > "$FAKE_BIN/docker"
    chmod +x "$FAKE_BIN/docker"

    run "$INSTALLER_PATH" --yes
    echo "Output: $output"
    # Check for progress bar artifacts in output
    [[ "$output" == *"["*"]"* ]] || [[ "$output" == *"Initializing"* ]]
}

@test "health: fails if health check fails after timeout" {
    # Mock docker compose ps to show not running
    echo -e '#!/bin/bash\nif [[ "$*" == *"compose ps"* ]]; then echo "{\"Service\": \"ultrafeeder\", \"Status\": \"starting\"}"; fi\nexit 0' > "$FAKE_BIN/docker"
    chmod +x "$FAKE_BIN/docker"
    
    # Mock curl to fail
    echo -e '#!/bin/bash\nexit 7' > "$FAKE_BIN/curl"
    chmod +x "$FAKE_BIN/curl"

    # Reduce timeout for testing
    export HEALTH_TIMEOUT=2
    run "$INSTALLER_PATH" --yes
    echo "Output: $output"
    [ "$status" -eq 20 ]
    [[ "$output" == *"Health check timeout"* ]]
}
