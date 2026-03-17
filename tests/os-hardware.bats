#!/usr/bin/env bats

setup() {
    export TMP_DIR="$(mktemp -d)"
    export INSTALLER_PATH="${BATS_TEST_DIRNAME}/../adsb-installer.sh"
    
    # Create fake bin dir
    export FAKE_BIN="$TMP_DIR/bin"
    mkdir -p "$FAKE_BIN"
    export PATH="$FAKE_BIN:$PATH"
    
    # Mock specific system commands only
    for cmd in docker lsusb modprobe timedatectl; do
        touch "$FAKE_BIN/$cmd"
        chmod +x "$FAKE_BIN/$cmd"
    done
    
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    export _ADSB_SKIP_DEPS=true
    
    # Default coords for headless runs
    export LAT=52.34 LON=4.89 ALT=10 FEEDER_TZ=UTC
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "hardware: detects RTL-SDR when present in lsusb" {
    # Mock lsusb to show an RTL-SDR
    echo "Bus 001 Device 004: ID 0bda:2832 Realtek Semiconductor Corp. RTL2832U DVB-T" > "$TMP_DIR/lsusb_output"
    echo -e "#!/bin/bash\ncat '$TMP_DIR/lsusb_output'" > "$FAKE_BIN/lsusb"
    chmod +x "$FAKE_BIN/lsusb"
    
    run "$INSTALLER_PATH" --dry-run --yes
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found RTL-SDR"* ]]
}

@test "hardware: fails if no RTL-SDR found" {
    echo "Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub" > "$TMP_DIR/lsusb_output"
    echo -e "#!/bin/bash\ncat '$TMP_DIR/lsusb_output'" > "$FAKE_BIN/lsusb"
    chmod +x "$FAKE_BIN/lsusb"
    
    echo "DEBUG: PATH=$PATH"
    echo "DEBUG: which lsusb=$(which lsusb)"
    echo "DEBUG: lsusb output=$($FAKE_BIN/lsusb)"

    run "$INSTALLER_PATH" --yes --config-only
    echo "Output: $output"
    echo "Status: $status"
    [ "$status" -eq 10 ]
    [[ "$output" == *"No RTL-SDR hardware detected"* ]]
}

@test "mutation: refuses to write to udev rules if it's a symlink" {
    # Mock lsusb so we get past the hardware probe
    echo "Bus 001 Device 004: ID 0bda:2832 Realtek Semiconductor Corp. RTL2832U DVB-T" > "$TMP_DIR/lsusb_output"
    echo -e "#!/bin/bash\ncat '$TMP_DIR/lsusb_output'" > "$FAKE_BIN/lsusb"
    chmod +x "$FAKE_BIN/lsusb"

    mkdir -p "$TMP_DIR/etc/udev/rules.d"
    ln -s /dev/null "$TMP_DIR/etc/udev/rules.d/rtl-sdr.rules"
    
    export UDEV_RULES_PATH="$TMP_DIR/etc/udev/rules.d/rtl-sdr.rules"
    run "$INSTALLER_PATH" --yes --config-only
    echo "Output: $output"
    [ "$status" -eq 10 ]
    [[ "$output" == *"symbolic link"* ]]
}

@test "permissions: checks docker socket permissions" {
    # Mock lsusb
    echo "Bus 001 Device 004: ID 0bda:2832 Realtek Semiconductor Corp. RTL2832U DVB-T" > "$TMP_DIR/lsusb_output"
    echo -e "#!/bin/bash\ncat '$TMP_DIR/lsusb_output'" > "$FAKE_BIN/lsusb"
    chmod +x "$FAKE_BIN/lsusb"

    export DOCKER_SOCKET="$TMP_DIR/docker.sock"
    # Create a dummy socket
    python3 -c "import socket as s; sock = s.socket(s.AF_UNIX); sock.bind('$DOCKER_SOCKET')"
    chmod 000 "$DOCKER_SOCKET" # Not writable
    
    # Mock confirm
    confirm() { return 0; }
    export -f confirm
    
    # Mock sudo
    echo -e '#!/bin/bash\nwhile [[ "$1" == -* ]]; do shift; done\nexec "$@"' > "$FAKE_BIN/sudo"
    /usr/bin/chmod +x "$FAKE_BIN/sudo"
    
    # Mock chmod
    echo -e '#!/bin/bash\necho "CHMOD_CALLED: $*"' > "$FAKE_BIN/chmod"
    /usr/bin/chmod +x "$FAKE_BIN/chmod"
    
    run "$INSTALLER_PATH" --yes --config-only
    echo "Output: $output"
    [[ "$output" == *"Docker socket permissions fixed"* ]]
    [[ "$output" == *"CHMOD_CALLED: 666 $DOCKER_SOCKET"* ]]
}

@test "kernel: blacklists RTL-SDR modules when requested" {
    # Mock lsusb
    echo "Bus 001 Device 004: ID 0bda:2832 Realtek Semiconductor Corp. RTL2832U DVB-T" > "$TMP_DIR/lsusb_output"
    echo -e "#!/bin/bash\n/usr/bin/cat '$TMP_DIR/lsusb_output'" > "$FAKE_BIN/lsusb"
    chmod +x "$FAKE_BIN/lsusb"

    export DOCKER_SOCKET="$TMP_DIR/docker.sock"
    touch "$DOCKER_SOCKET"
    chmod 666 "$DOCKER_SOCKET"

    export BLACKLIST_PATH="$TMP_DIR/exclusions-rtl2832.conf"
    export _ADSB_YES=true
    export CALL_LOG="$TMP_DIR/call.log"
    touch "$CALL_LOG"

    # Mock sudo to preserve PATH and just run the command
    echo -e '#!/bin/bash\nwhile [[ "$1" == -* ]]; do shift; done\nexec "$@"' > "$FAKE_BIN/sudo"
    chmod +x "$FAKE_BIN/sudo"

    # Mock tee, modprobe, depmod, update-initramfs to write to CALL_LOG
    for cmd in tee modprobe depmod update-initramfs; do
        echo -e "#!/bin/bash\necho \"${cmd^^}_CALLED: \$*\" >> \"$CALL_LOG\"" > "$FAKE_BIN/$cmd"
        # For tee, also handle stdin to prevent blocking
        if [[ "$cmd" == "tee" ]]; then
            echo -e "cat > /dev/null" >> "$FAKE_BIN/$cmd"
        fi
        chmod +x "$FAKE_BIN/$cmd"
    done
    
    run "$INSTALLER_PATH" --yes --config-only
    echo "Output: $output"
    echo "Call Log:"
    cat "$CALL_LOG"
    [ "$status" -eq 0 ]
    
    grep -q "TEE_CALLED: $BLACKLIST_PATH" "$CALL_LOG"
    grep -q "MODPROBE_CALLED: -r dvb_core" "$CALL_LOG"
    grep -q "DEPMOD_CALLED: -a" "$CALL_LOG"
    grep -q "UPDATE-INITRAMFS_CALLED: -u" "$CALL_LOG"
}
