#!/usr/bin/env bash
# --- Guard ---
[[ -n "${_WIZARD_UI_SH_SOURCED:-}" ]] && return 0
_WIZARD_UI_SH_SOURCED=1

# --- Strict Mode ---
set -Eeuo pipefail
# --- Constants ---
# shellcheck disable=SC2034
BOLD="\033[1m"
# shellcheck disable=SC2034
NC="\033[0m"
# shellcheck disable=SC2034
CYAN="\033[0;36m"
# shellcheck disable=SC2034
GREEN="\033[0;32m"
# shellcheck disable=SC2034
RED="\033[0;31m"

# --- UI Helpers ---
show_welcome() {
    clear
    draw_header "ADS-B INSTALLER v${VERSION:-1.0.0}"
    echo -e "Welcome to the SDR-Enthusiasts ADS-B Docker stack installer."
    echo -e "This wizard will guide you through the configuration process.\n"
    
    if [[ "${_ADSB_YES:-false}" == "true" ]]; then
        return 0
    fi
    
    read -p "Press [Enter] to begin..." -r
}

check_resume() {
    if [[ ! -f "$STATE_FILE" ]]; then return 1; fi
    
    # Load state
    load_config  # This will also load .installer_state if we call it correctly
    
    # Simple manual parse if load_config only does .env
    local last_stage
    last_stage=$(grep "LAST_STAGE=" "$STATE_FILE" 2>/dev/null | cut -d'"' -f2 || echo "0")
    
    if [[ -n "$last_stage" && "$last_stage" != "0" && "$last_stage" != "100" ]]; then
        draw_header "RESUME INSTALLATION"
        echo -e "A previous installation attempt was found (Stage: $last_stage)."
        
        if [[ "${_ADSB_YES:-false}" == "true" ]]; then
            info "Headless mode: Resuming from stage $last_stage"
            return 0
        fi
        
        local choice
        read -p "Would you like to resume? [Y/n]: " -r choice
        case "$choice" in
            [nN]*)
                info "Starting fresh installation..."
                rm -f "$STATE_FILE"
                return 1
                ;;
            *)
                info "Resuming..."
                return 0
                ;;
        esac
    fi
    return 1
}

check_quick_path() {
    # 1. Check if stack is already deployed
    if ! is_stack_deployed; then
        return 1
    fi
    
    # Load existing config to get current values
    load_config
    
    # 2. Check if we have core config already
    if [[ -z "${FEEDER_LAT:-}" || -z "${FEEDER_LONG:-}" ]]; then
        return 1
    fi
    
    draw_header "QUICK PATH"
    echo -e "An active ADS-B deployment was detected."
    echo -e "Current Location: ${FEEDER_LAT}, ${FEEDER_LONG} (${FEEDER_TZ:-UTC})"
    echo ""
    
    if [[ "${_ADSB_YES:-false}" == "true" ]]; then
        info "Headless mode: Jumping directly to feeder selection."
        return 0
    fi
    
    local choice
    read -p "Would you like to skip core configuration and jump to feeder selection? [Y/n]: " -r choice
    case "$choice" in
        [nN]*)
            return 1
            ;;
        *)
            info "Jumping to feeder selection..."
            return 0
            ;;
    esac
}

# --- Interactive Multi-Select ---
prompt_multi_select() {
    local -n _options=$1
    local -n _selected=$2
    local prompt_text="$3"
    
    local cursor=0
    local menu_size=${#_options[@]}
    
    # If not a terminal, we can't do interactive
    if [[ ! -t 0 ]]; then
        return 0
    fi

    # Skip if headless
    if [[ "${_ADSB_YES:-false}" == "true" ]]; then
        return 0
    fi

    echo -e "\n${BOLD}${prompt_text}${NC}"
    echo -e "(Use arrow keys to move, Space to toggle, Enter to finish)\n"

    # Hide cursor
    tput civis || true

    while true; do
        # Render menu
        for i in "${!_options[@]}"; do
            local marker="  "
            if [[ $i -eq $cursor ]]; then marker="${CYAN}>${NC} "; fi
            
            local checkbox="[ ]"
            if [[ "${_selected[$i]}" == "true" ]]; then checkbox="[${GREEN}x${NC}]"; fi
            
            echo -e "\r${marker}${checkbox} ${_options[$i]}"
        done

        # Move cursor back up to redraw next time
        tput cuu "$menu_size" || true

        # Read key
        local key
        IFS= read -rsn1 key
        case "$key" in
            $'\x1b') # Escape sequence
                read -rsn2 -t 0.1 rest || continue
                case "$rest" in
                    '[A') cursor=$(( (cursor - 1 + menu_size) % menu_size )) ;; # Up
                    '[B') cursor=$(( (cursor + 1) % menu_size )) ;;             # Down
                esac
                ;;
            " ") # Toggle
                if [[ "${_selected[cursor]}" == "true" ]]; then
                    _selected[cursor]=false
                else
                    _selected[cursor]=true
                fi
                ;;
            "") # Enter
                break
                ;;
        esac
    done

    # Show cursor and clean up
    tput cnorm || true
    # Jump to bottom of menu
    tput cud "$menu_size" || true
    echo ""
}

prompt_input() {
    local var_name="$1"
    local prompt_text="$2"
    local default_val="${3:-}"
    local validation_type="${4:-}" # LAT, LON, ALT, FA_KEY, etc.
    local options="${5:-}"         # e.g., "SECURE"
    
    # Skip if value exists and we are in a context that allows skipping (Headless or Resuming/QuickPath)
    if [[ "${_ADSB_YES:-false}" == "true" ]] || [[ "${ADSB_RESUMING:-false}" == "true" ]]; then
        local existing_val="${!var_name:-}"
        if [[ -n "$existing_val" ]]; then
            local is_valid=true
            if [[ -n "$validation_type" ]]; then
                if [[ "$validation_type" == "LAT" || "$validation_type" == "LON" ]]; then
                    validate_coordinate "$validation_type" "$existing_val" || is_valid=false
                elif [[ "$validation_type" == "ALT" ]]; then
                    [[ "$existing_val" =~ ^[0-9]+$ ]] || is_valid=false
                elif [[ "$validation_type" == "TZ" ]]; then
                    if command -v timedatectl &>/dev/null; then
                        timedatectl list-timezones | grep -qx "$existing_val" || is_valid=false
                    fi
                elif [[ "$validation_type" == "FA_KEY" ]]; then
                    [[ "$existing_val" =~ ^([a-fA-F0-9]{32}|[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})$ ]] || is_valid=false
                elif [[ "$validation_type" == "FR24_KEY" ]]; then
                    [[ "$existing_val" =~ ^[a-zA-Z0-9]{16}$ ]] || is_valid=false
                fi
            fi
            
            if [[ "$is_valid" == "true" ]]; then
                # Only skip if it was already in .env (to avoid skipping defaults in fresh runs)
                # Headless mode always skips if value is valid.
                if grep -q "^${var_name}=" "$ENV_FILE" 2>/dev/null || [[ "${_ADSB_YES:-false}" == "true" ]]; then
                    export "$var_name"="$existing_val"
                    safe_write_env "$var_name" "$existing_val"
                    return 0
                fi
            fi
        fi
    fi

    # Final bypass for headless mode even if no existing value or invalid
    if [[ "${_ADSB_YES:-false}" == "true" ]]; then
        local val="${!var_name:-$default_val}"
        export "$var_name"="$val"
        safe_write_env "$var_name" "$val"
        return 0
    fi
    
    local value
    local retries=0
    local silent_flag=""
    if [[ "$options" == *"SECURE"* ]]; then
        silent_flag="-s"
    fi

    while (( retries < 3 )); do
        # Use printf for prompt to handle -s read better
        printf "%s [%s]: " "$prompt_text" "${!var_name:-$default_val}"
        # shellcheck disable=SC2229
        read -r ${silent_flag} value
        echo # Newline after read
        
        value="${value:-${!var_name:-$default_val}}"
        
        if [[ -n "$validation_type" ]]; then
            local valid=false
            if [[ "$validation_type" == "LAT" || "$validation_type" == "LON" ]]; then
                if validate_coordinate "$validation_type" "$value"; then valid=true; fi
            elif [[ "$validation_type" == "ALT" ]]; then
                if [[ "$value" =~ ^[0-9]+$ ]]; then valid=true; fi
            elif [[ "$validation_type" == "TZ" ]]; then
                # Check against timedatectl if available, else allow anything non-empty
                if command -v timedatectl &>/dev/null; then
                    if timedatectl list-timezones | grep -qx "$value"; then valid=true; fi
                else
                    if [[ -n "$value" ]]; then valid=true; fi
                fi
            elif [[ "$validation_type" == "FA_KEY" ]]; then
                if [[ "$value" =~ ^([a-fA-F0-9]{32}|[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})$ ]]; then valid=true; fi
            elif [[ "$validation_type" == "FR24_KEY" ]]; then
                if [[ "$value" =~ ^[a-zA-Z0-9]{16}$ ]]; then valid=true; fi
            elif [[ "$validation_type" == "STATION_ID" ]]; then
                if [[ "$value" =~ ^[a-z0-9-]{3,32}$ ]]; then valid=true; fi
            fi
            
            if [[ "$valid" == "true" ]]; then
                export "$var_name"="$value"
                safe_write_env "$var_name" "$value"
                return 0
            fi
        else
            export "$var_name"="$value"
            safe_write_env "$var_name" "$value"
            return 0
        fi
        
        (( retries += 1 ))
        warn "Invalid input format for $var_name. Retries remaining: $(( 3 - retries ))"
    done
    
    error "Maximum retries exceeded for $var_name."
    exit 30
}

run_wizard() {
    show_welcome
    
    local resuming=false
    local last_stage=0
    
    # Check for resume or quick path
    if check_resume; then
        resuming=true
        last_stage=$(grep "LAST_STAGE=" "$STATE_FILE" | cut -d'"' -f2 || echo "0")
    elif check_quick_path; then
        resuming=true
        last_stage=30
    else
        update_state "LAST_STAGE" "10"
    fi
    export ADSB_RESUMING="$resuming"
    
    # Stage 30: Core Config
    if [[ "$resuming" == false || "$last_stage" -lt 30 ]]; then
        draw_header "CORE CONFIGURATION"
        prompt_input "FEEDER_LAT" "Enter Latitude (e.g., 52.3702)" "" "LAT"
        prompt_input "FEEDER_LONG" "Enter Longitude (e.g., 4.8952)" "" "LON"
        prompt_input "FEEDER_ALT_M" "Enter Altitude in meters (e.g., 10)" "0" "ALT"
        prompt_input "FEEDER_TZ" "Enter Timezone" "UTC" "TZ"
        update_state "LAST_STAGE" "30"
    fi
    
    # Stage 40: Feeder Selection
    if [[ "$resuming" == false || "$last_stage" -lt 40 ]]; then
        draw_header "FEEDER SELECTION"
        if [[ "${_ADSB_YES:-false}" == "false" ]]; then
            # shellcheck disable=SC2034
            local -a feeder_names=(
                "FlightAware (fa)" 
                "Flightradar24 (fr24)" 
                "Plane-Watch (planewatch)" 
                "AirNav RadarBox (rbfeeder)" 
                "PlaneFinder (pfclient)" 
                "ADSBHub (adsbhub)" 
                "OpenSky Network (opensky)" 
                "RadarVirtuel (radarvirtuel)"
            )
            local -a feeder_keys=(fa fr24 planewatch rbfeeder pfclient adsbhub opensky radarvirtuel)
            local -a feeder_selected=()
            
            # Initialize selection based on current environment
            for key in "${feeder_keys[@]}"; do
                local var_name="ENABLE_${key^^}"
                if [[ "${!var_name:-false}" == "true" ]]; then
                    feeder_selected+=(true)
                else
                    feeder_selected+=(false)
                fi
            done

            # Interactive selection or fallback
            if [[ -t 0 ]]; then
                prompt_multi_select feeder_names feeder_selected "Select the feeder services you wish to enable:"
            else
                # Fallback for piped input (legacy numeric input reading)
                local choices
                if read -t 1 -r choices; then
                    for choice in $choices; do
                        if [[ "$choice" =~ ^[1-8]$ ]]; then
                            feeder_selected[choice-1]=true
                        fi
                    done
                fi
            fi
            
            # Apply selection
            for i in "${!feeder_keys[@]}"; do
                local key="${feeder_keys[$i]}"
                local var_name="ENABLE_${key^^}"
                if [[ "${feeder_selected[$i]}" == "true" ]]; then
                    export "$var_name=true"
                    safe_write_env "$var_name" "true"
                else
                    export "$var_name=false"
                    safe_write_env "$var_name" "false"
                fi
            done
        else
            info "Resuming or Headless: Keeping existing feeder selection."
        fi

        # Modern Aggregators (Internal to ultrafeeder)
        draw_header "AGGREGATOR CONFIGURATION"
        if [[ "${_ADSB_YES:-false}" == "true" ]]; then
            export ENABLE_AGGREGATORS="${ENABLE_AGGREGATORS:-true}"
            info "Headless mode: Enabling modern aggregator feeds (ADSB.lol, Airplanes.live, etc.) by default."
        else
            echo -e "Enable feeding to modern aggregators?\n(ADSB.lol, Airplanes.live, ADSBExchange, etc.)"
            local agg_default="Y/n"
            [[ "${ENABLE_AGGREGATORS:-true}" == "false" ]] && agg_default="y/N"
            
            local choice_agg
            read -p "[$agg_default]: " -r choice_agg
            case "$choice_agg" in
                [nN]*) export ENABLE_AGGREGATORS=false ;;
                [yY]*) export ENABLE_AGGREGATORS=true ;;
                "") # Keep existing if any, else default true
                    export ENABLE_AGGREGATORS="${ENABLE_AGGREGATORS:-true}"
                    ;;
            esac
        fi
        safe_write_env "ENABLE_AGGREGATORS" "${ENABLE_AGGREGATORS:-true}"
        
        # Backward compatibility for any logic still checking these
        export ENABLE_ADSBLOL="${ENABLE_AGGREGATORS:-true}"
        export ENABLE_AIRPLANES="${ENABLE_AGGREGATORS:-true}"
        safe_write_env "ENABLE_ADSBLOL" "${ENABLE_ADSBLOL}"
        safe_write_env "ENABLE_AIRPLANES" "${ENABLE_AIRPLANES}"

        update_state "LAST_STAGE" "40"
    fi

    # Stage 50: Feeder Keys
    if [[ "$resuming" == false || "$last_stage" -lt 50 ]]; then
        if [[ "${ENABLE_FA:-false}" == "true" ]] && [[ -z "${PIAWARE_FEEDER_ID:-}" ]]; then
            prompt_input "PIAWARE_FEEDER_ID" "Enter FlightAware Sharing Key" "" "FA_KEY" "SECURE"
        fi
        if [[ "${ENABLE_FR24:-false}" == "true" ]] && [[ -z "${FR24_SHARING_KEY:-}" ]]; then
            prompt_input "FR24_SHARING_KEY" "Enter Flightradar24 Sharing Key" "" "FR24_KEY" "SECURE"
        fi
        if [[ "${ENABLE_PLANEWATCH:-false}" == "true" ]] && [[ -z "${PLANEWATCH_KEY:-}" ]]; then
            prompt_input "PLANEWATCH_KEY" "Enter Plane-Watch API Key" "" "" "SECURE"
        fi
        if [[ "${ENABLE_RBFEEDER:-false}" == "true" ]] && [[ -z "${AIRNAVRADAR_SHARING_KEY:-}" ]]; then
            prompt_input "AIRNAVRADAR_SHARING_KEY" "Enter RadarBox Sharing Key" "" "" "SECURE"
        fi
        if [[ "${ENABLE_PFCLIENT:-false}" == "true" ]] && [[ -z "${PLANEFINDER_SHARECODE:-}" ]]; then
            prompt_input "PLANEFINDER_SHARECODE" "Enter PlaneFinder Share Code" "" "" "SECURE"
        fi
        if [[ "${ENABLE_ADSBHUB:-false}" == "true" ]] && [[ -z "${ADSBHUB_STATION_KEY:-}" ]]; then
            prompt_input "ADSBHUB_STATION_KEY" "Enter ADSBHub Station Key" "" "" "SECURE"
        fi
        if [[ "${ENABLE_OPENSKY:-false}" == "true" ]]; then
            if [[ -z "${OPENSKY_USERNAME:-}" ]]; then
                prompt_input "OPENSKY_USERNAME" "Enter OpenSky Network Username" "" ""
            fi
            if [[ -z "${OPENSKY_SERIAL:-}" ]]; then
                prompt_input "OPENSKY_SERIAL" "Enter OpenSky Network Serial (Optional)" "" ""
            fi
        fi
        if [[ "${ENABLE_RADARVIRTUEL:-false}" == "true" ]] && [[ -z "${RV_FEEDER_KEY:-}" ]]; then
            prompt_input "RV_FEEDER_KEY" "Enter RadarVirtuel Feeder Key" "" "" "SECURE"
        fi
        update_state "LAST_STAGE" "50"
    fi
    
    update_state "LAST_STAGE" "100"  # Mark as complete for now
}
