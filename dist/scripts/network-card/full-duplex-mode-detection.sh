#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/network.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start network card duplex mode detection"
YAML=$(generate_yaml_detection "full_duplex_mode_results")$'\n'

# get the bond network card
set +e
log_debug "Start getting all bond interfaces"
bonds=$(get_bond_interfaces)
ret=$?
log_debug "$(echo "$bonds" | tr '\n' ' ')"
set -e

if [ $ret -ne 0 ] || [ -z "$bonds" ]; then
    log_err "No bond interfaces found"
    YAML+=$(generate_yaml_entry "No bond" "Unknown" "No bond interfaces found" "error")$'\n'
    log_debug "$YAML"
    # shellcheck disable=SC2154
    RESULT=$(echo "$YAML" | jinja2 network-card.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
    log_result "$RESULT"

    set +e
    log_debug "Start posting detection result"
    response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
    # response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
    ret=$?
    log_debug "$(echo "$response" | tr '\n' ' ')"
    set -e
    exit $ret
fi

# detect bond network card and physical network card
for bond in $bonds; do
    log_info "Start checking network card $bond"

    set +e
    log_debug "Start getting all slave interfaces for $bond"
    slaves=$(get_bond_slaves "$bond")
    ret=$?
    log_debug "$(echo "$slaves" | tr '\n' ' ')"
    set -e

    if [ $ret -ne 0 ] || [ -z "$slaves" ]; then
        log_err "Slave interfaces not found for $bond"
        YAML+=$(generate_yaml_entry "$bond" "Unknown" "No slave interfaces found" "error")$'\n'
        continue
    fi

    log_debug "Get Duplex status for $bond"
    duplex=$(ethtool "$bond" 2>/dev/null | grep "Duplex:" | awk '{print $2}')
    duplex=${duplex:-Unknown}

    case "$duplex" in
        Full)
            all_full=true
            for slave in $slaves; do
                log_debug "Get Duplex status for $slave"
                slave_duplex=$(ethtool "$slave" 2>/dev/null | grep "Duplex:" | awk '{print $2}')
                slave_duplex=${slave_duplex:-Unknown}
                case "$slave_duplex" in
                    Full)
                        # continue to next slave
                        ;;
                    Half)
                        log_warn "$slave is running on Half Duplex"
                        YAML+=$(generate_yaml_entry "$bond" "Half" "Slave interface $slave is running on Half Duplex" "warn")$'\n'
                        all_full=false
                        break
                        ;;
                    Unknown | *)
                        log_err "$slave is running on Unknown Duplex"
                        YAML+=$(generate_yaml_entry "$bond" "Unknown" "Slave interface $slave is running on Unknown Duplex" "error")$'\n'
                        all_full=false
                        break
                        ;;
                esac
            done
            if [ "$all_full" = true ]; then
                log_info "$bond and all its slaves are running on Full Duplex"
                YAML+=$(generate_yaml_entry "$bond" "Full" "" "")$'\n'
            fi
            ;;
        Half)
            log_warn "$bond is running on Half Duplex"
            YAML+=$(generate_yaml_entry "$bond" "Half" "$bond is running on Half Duplex" "warn")$'\n'
            ;;
        Unknown | *)
            log_err "$bond is running on Unknown Duplex"
            YAML+=$(generate_yaml_entry "$bond" "Unknown" "$bond is running on Unknown Duplex" "error")$'\n'
            ;;
    esac

    log_info "Start checking bond subinterfaces for network card $bond"

    set +e
    log_debug "Start getting all subinterfaces for $bond"
    subinterfaces=$(get_bond_subinterfaces "$bond")
    ret=$?
    log_debug "$(echo "$subinterfaces" | tr '\n' ' ')"
    set -e

    if [ $ret -ne 0 ] || [ -z "$subinterfaces" ]; then
        log_warn "Subinterfaces not found for $bond"
    fi

    for subinterface in $subinterfaces; do
        log_debug "Get Duplex status for $subinterface"
        subinterface_duplex=$(ethtool "$subinterface" 2>/dev/null | grep "Duplex:" | awk '{print $2}')
        subinterface_duplex=${subinterface_duplex:-Unknown}

        case "$subinterface_duplex" in
            Full)
                YAML+=$(generate_yaml_entry "$subinterface" "Full" "" "")$'\n'
                ;;
            Half)
                log_warn "$subinterface is running on Half Duplex"
                YAML+=$(generate_yaml_entry "$subinterface" "Half" "Subinterface $subinterface is running on Half Duplex" "warn")$'\n'
                break
                ;;
            Unknown | *)
                log_err "$subinterface is running on Unknown Duplex"
                YAML+=$(generate_yaml_entry "$subinterface" "Unknown" "Subinterface $subinterface is running on Unknown Duplex" "error")$'\n'
                break
                ;;
        esac
    done
done

log_debug "$YAML"
# shellcheck disable=SC2154
RESULT=$(echo "$YAML" | jinja2 network-card.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result "$RESULT"

set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret
