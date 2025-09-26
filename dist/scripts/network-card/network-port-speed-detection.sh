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

log_info "Start network card speed detection"
YAML=$(generate_yaml_detection "network_port_speed_results")$'\n'

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
	response=$(send_post "asdas" "$RESULT" admin)
	# response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
	ret=$?
	log_debug "$(echo "$response" | tr '\n' ' ')"
	set -e

	exit $ret
fi

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

	set +e
	if [[ "$bond" == "bond0" ]]; then
		if ((speed < 1000)); then
			log_warn "bond0 speed is below 1Gbps: ${speed}Mbps, may impact manage network"
			YAML+=$(generate_yaml_entry "$bond" "${speed}Mbps" "bond0 speed below 1Gbps may impact manage network" "warning")$'\n'
		else
			YAML+=$(generate_yaml_entry "$bond" "${speed}Mbps" "" "")$'\n'
		fi
	else
		if ((speed < 10000)); then
			log_err "$bond speed is too low: ${speed}Mbps"
			YAML+=$(generate_yaml_entry "$bond" "${speed}Mbps" "$bond speed is too low" "error")$'\n'
		elif ((speed < 20000)); then
			log_warn "$bond speed is below optimal: ${speed}Mbps"
			YAML+=$(generate_yaml_entry "$bond" "${speed}Mbps" "$bond speed is low" "warn")$'\n'
		else
			log_info "$bond speed is : ${speed}Mbps"
			YAML+=$(generate_yaml_entry "$bond" "${speed}Mbps" "" "")$'\n'
		fi
	fi
	set -e
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
