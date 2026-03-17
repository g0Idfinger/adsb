#!/usr/bin/env bats

setup() {
    export TMP_DIR="$(mktemp -d)"
    export INSTALLER_DIR="$TMP_DIR"
    export LIB_DIR="${BATS_TEST_DIRNAME}/../lib"
    export TEMPLATES_DIR="${BATS_TEST_DIRNAME}/../templates"
    
    # Mock bin dir
    export FAKE_BIN="$TMP_DIR/bin"
    mkdir -p "$FAKE_BIN"
    export PATH="$FAKE_BIN:$PATH"
    
    # Source libraries
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/state-manager.sh"
    source "$LIB_DIR/os-config.sh"
    source "$LIB_DIR/docker-logic.sh"
    
    # Mock basic commands
    touch "$FAKE_BIN/lsusb" "$FAKE_BIN/rtl_test" "$FAKE_BIN/rtl_eeprom" "$FAKE_BIN/docker"
    chmod +x "$FAKE_BIN/lsusb" "$FAKE_BIN/rtl_test" "$FAKE_BIN/rtl_eeprom" "$FAKE_BIN/docker"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "uat: get_sdr_count detects multiple SDRs" {
    echo -e "#!/bin/bash\necho -e \"Bus 001 Device 004: ID 0bda:2832 Realtek\nBus 001 Device 005: ID 0bda:2838 Realtek\"" > "$FAKE_BIN/lsusb"
    chmod +x "$FAKE_BIN/lsusb"
    
    run get_sdr_count
    [ "$output" -eq 2 ]
}

@test "uat: get_sdr_serials uses rtl_test" {
    echo -e "#!/bin/bash\necho 'Serial number: 1090'\necho 'Serial number: 978'" > "$FAKE_BIN/rtl_test"
    chmod +x "$FAKE_BIN/rtl_test"
    
    run get_sdr_serials
    [[ "$output" == *"1090"* ]]
    [[ "$output" == *"978"* ]]
}

@test "uat: assemble_compose includes uat.yml when ENABLE_UAT=true" {
    export ENABLE_UAT=true
    export FEEDER_LAT=52.34
    export FEEDER_LONG=4.89
    
    # Create required files for assemble_compose
    mkdir -p "$TMP_DIR/compose"
    mkdir -p "$TMP_DIR/templates"
    echo "services:" > "$TMP_DIR/templates/base.yml"
    echo "services:" > "$TMP_DIR/templates/uat.yml"
    echo "networks:" > "$TMP_DIR/templates/networks.yml"
    
    run assemble_compose
    [ "$status" -eq 0 ]
    [ -f "$TMP_DIR/docker-compose.yml" ]
    grep -q "compose/uat.yml" "$TMP_DIR/docker-compose.yml"
}

@test "uat: ultrafeeder config includes dump978 when ENABLE_UAT=true" {
    export ENABLE_UAT=true
    run get_ultrafeeder_config
    [[ "$output" == *"adsb,dump978,30978;"* ]]
}

@test "uat: reserialise_sdr calls rtl_eeprom with correct args" {
    echo -e "#!/bin/bash\necho \"CALLED: \$*\"" > "$FAKE_BIN/rtl_eeprom"
    
    run reserialise_sdr "1234" "1"
    [[ "$output" == *"CALLED: -d 1 -s 1234"* ]]
}
