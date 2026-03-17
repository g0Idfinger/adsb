#!/usr/bin/env bats

setup() {
    export TMP_DIR="$(mktemp -d)"
    export LIB_DIR="${BATS_TEST_DIRNAME}/../lib"
    export TEMPLATES_DIR="${TMP_DIR}/templates"
    mkdir -p "$TEMPLATES_DIR"
    
    # Create fake templates
    echo "services: base: image: base" > "${TEMPLATES_DIR}/base.yml"
    echo "networks: adsb: driver: bridge" > "${TEMPLATES_DIR}/networks.yml"
    echo "services: fa: image: fa" > "${TEMPLATES_DIR}/fa.yml"
    echo "services: fr24: image: fr24" > "${TEMPLATES_DIR}/fr24.yml"
    echo "services: planewatch: image: pw" > "${TEMPLATES_DIR}/planewatch.yml"
    echo "services: rbfeeder: image: rb" > "${TEMPLATES_DIR}/rbfeeder.yml"
    echo "services: pfclient: image: pf" > "${TEMPLATES_DIR}/pfclient.yml"
    echo "services: adsbhub: image: hub" > "${TEMPLATES_DIR}/adsbhub.yml"
    echo "services: opensky: image: sky" > "${TEMPLATES_DIR}/opensky.yml"
    echo "services: radarvirtuel: image: rv" > "${TEMPLATES_DIR}/radarvirtuel.yml"
    
    export INSTALLER_DIR="$TMP_DIR"
    export COMPOSE_TARGET="${TMP_DIR}/docker-compose.yml"
    
    # Mock info/error
    info() { :; }
    error() { :; }
    export -f info error
    export _ADSB_SKIP_DEPS=true
    export _ADSB_LOCKFILE="$TMP_DIR/adsb-installer.lock"
    
    source "${LIB_DIR}/docker-logic.sh"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "deployment: assemble_compose includes only base and networks by default" {
    assemble_compose
    
    run grep -q "path: compose/ultrafeeder.yml" "$COMPOSE_TARGET"
    [ "$status" -eq 0 ]
    
    run grep -q "path: compose/fa.yml" "$COMPOSE_TARGET"
    [ "$status" -eq 1 ]
    
    run grep -q "networks:" "$COMPOSE_TARGET"
    [ "$status" -eq 0 ]
    
    [ -f "${INSTALLER_DIR}/compose/ultrafeeder.yml" ]
}

@test "deployment: assemble_compose includes FlightAware when enabled" {
    export ENABLE_FA=true
    assemble_compose
    
    run grep -q "path: compose/fa.yml" "$COMPOSE_TARGET"
    [ "$status" -eq 0 ]
    [ -f "${INSTALLER_DIR}/compose/fa.yml" ]
}

@test "deployment: assemble_compose includes multi feeders" {
    export ENABLE_FA=true
    export ENABLE_FR24=true
    assemble_compose
    
    run grep -q "path: compose/fa.yml" "$COMPOSE_TARGET"
    [ "$status" -eq 0 ]
    run grep -q "path: compose/fr24.yml" "$COMPOSE_TARGET"
    [ "$status" -eq 0 ]
    [ -f "${INSTALLER_DIR}/compose/fa.yml" ]
    [ -f "${INSTALLER_DIR}/compose/fr24.yml" ]
}

@test "deployment: assemble_compose excludes disabled feeders" {
    export ENABLE_FA=false
    export ENABLE_FR24=true
    assemble_compose
    
    run grep -q "path: compose/fa.yml" "$COMPOSE_TARGET"
    [ "$status" -eq 1 ]
    run grep -q "path: compose/fr24.yml" "$COMPOSE_TARGET"
    [ "$status" -eq 0 ]
    [ ! -f "${INSTALLER_DIR}/compose/fa.yml" ]
    [ -f "${INSTALLER_DIR}/compose/fr24.yml" ]
}

@test "deployment: assemble_compose includes graphs when enabled" {
    export ENABLE_GRAPHS=true
    
    # Mock template exists
    mkdir -p "${TEMPLATES_DIR}"
    echo "services: tar1090: image: graphs" > "${TEMPLATES_DIR}/graphs.yml"
    
    assemble_compose
    
    run grep -q "path: compose/graphs.yml" "$COMPOSE_TARGET"
    [ "$status" -eq 0 ]
    [ -f "${INSTALLER_DIR}/compose/graphs.yml" ]
}

@test "deployment: assemble_compose includes all 5 new feeders" {
    export ENABLE_PLANEWATCH=true
    export ENABLE_RBFEEDER=true
    export ENABLE_PFCLIENT=true
    export ENABLE_ADSBHUB=true
    export ENABLE_OPENSKY=true
    export ENABLE_RADARVIRTUEL=true
    
    assemble_compose
    
    for f in planewatch rbfeeder pfclient adsbhub opensky radarvirtuel; do
        run grep -q "path: compose/${f}.yml" "$COMPOSE_TARGET"
        [ "$status" -eq 0 ]
        [ -f "${INSTALLER_DIR}/compose/${f}.yml" ]
    done
}
