#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/network.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start network card connection mode detection"
YAML=$(generate_yaml_detection "network_port_connection_mode_results")$'\n'

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
	exit 0
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

	log_debug "Get speed for $bond"
	speed=$(ethtool "$bond" | grep -Po '(?<=Speed: )\d+')
	if [ -z "$speed" ]; then
		log_warn "bond interface $bond speed is unknown"
		YAML+=$(generate_yaml_entry "$bond" "Unknown" "Bond interface $bond speed is unknown" "error")$'\n'
		continue
	fi

	slave_speeds=()
	total_speed=0
	has_empty_speed=false
	for slave in $slaves; do

		set +e
		log_debug "Start getting slave interface $slave max speed"
		slave_speed=$(get_max_supported_speed "$slave")
		ret=$?
		log_debug "$(echo "$slave_speed" | tr '\n' ' ')"
		set -e

		if [ $ret -ne 0 ] || [[ -z "$slave_speed" ]]; then
			log_warn "bond slave $slave speed is unknown"
			YAML+=$(generate_yaml_entry "$bond" "Unknown" "$bond slave interface $slave speed is unknown" "warn")$'\n'
			has_empty_speed=true
			break
		fi
		slave_speeds+=("$slave_speed")
		((total_speed += slave_speed))
	done

	if $has_empty_speed; then
		continue
	fi

	set +e
	if [[ "$bond" == "bond0" ]]; then
		mismatch=false
		for s in "${slave_speeds[@]}"; do
			if [[ "$speed" -ne "$s" ]]; then
				mismatch=true
				break
			fi
		done
		if $mismatch; then
			log_warn "bond0 speed $speed does not match all slave speeds: ${slave_speeds[*]}"
			YAML+=$(generate_yaml_entry "$bond" "${speed}Mbps" "$bond speed mismatch with slaves" "warn")$'\n'
		else
			log_info "bond0 speed $speed matches all slave speeds"
			YAML+=$(generate_yaml_entry "$bond" "The bond0 network card speed matches the slave's maximum speed" "" "")$'\n'
		fi
	else
		if [[ "$speed" -ne "$total_speed" ]]; then
			log_warn "$bond speed $speed does not equal sum of slave speeds $total_speed"
			YAML+=$(generate_yaml_entry "$bond" "${speed}Mbps" "$bond speed mismatch with sum of slaves" "warn")$'\n'
		else
			log_info "$bond speed $speed equals sum of slave speeds $total_speed"
			YAML+=$(generate_yaml_entry "$bond" "The $bond network card speed matches the slave's maximum speed" "" "")$'\n'
		fi
	fi
	set -e
done

log_debug "$YAML"
# shellcheck disable=SC2154
RESULT=$(echo "$YAML" | jinja2 network-card.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result "$RESULT"
