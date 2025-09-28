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

log_info "Start network card vlan conflict detection"
YAML=$(generate_yaml_detection "network_card_conflict_results")$'\n'

# get the bond network card
set +e
log_debug "Start getting all bond interfaces"
bonds=$(get_bond_interfaces)
ret=$?
log_debug "$(echo "$bonds" | tr '\n' ' ')"
set -e

if [ $ret -ne 0 ] || [ -z "$bonds" ]; then
	log_err "No bond interfaces found"
	YAML+=$(generate_yaml_entry "No bond" "" "There is no bond network card, so there is no VLAN conflict" "warn")$'\n'
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

# get the provider-networks.kubeovn.io
set +e
log_debug "Start getting all provider-networks"
provider_networks=$(get_provider_networks)
ret=$?
log_debug "$(echo "$provider_networks" | tr '\n' ' ')"
set -e

if [ $ret -ne 0 ]; then
	log_warn "Get provider-networks failed"
	YAML+=$(generate_yaml_entry "provider-networks" "Failed" "Get provider-networks failed" "warn")$'\n'
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

if [ -z "$provider_networks" ]; then
	log_err "There is no provider-networks resource found"
	YAML+=$(generate_yaml_entry "provider-networks" "Not found" "There is no provider-networks resource found" "error")$'\n'
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

for provider_network in $provider_networks; do
	# get the provider-networks.kubeovn.io bonding interface
	set +e
	log_debug "Start getting provider-networks $provider_network bonding interface"
	default_interface=$(get_default_interface "$provider_network")
	ret=$?
	log_debug "$(echo "$default_interface" | tr '\n' ' ')"
	set -e

	if [ $ret -ne 0 ] || [ -z "$default_interface" ]; then
		log_err "Failed to get defaultInterface spec by provider-networks.kubeovn.io $provider_network"
		YAML+=$(generate_yaml_entry "$provider_network" "defaultInterface Unbound" "$provider_network doesn't bonding any interface" "error")$'\n'
		continue
	fi

	# get the provider-networks.kubeovn.io bonding interface
	set +e
	log_debug "Start getting provider-networks $provider_network bonding vlan ids"
	provider_network_vlans=$(get_provider_network_vlans "$provider_network")
	ret=$?
	log_debug "$(echo "$provider_network_vlans" | tr '\n' ' ')"
	set -e

	if [ $ret -ne 0 ]; then
		log_err "Failed to get vlan ids for provider-networks.kubeovn.io $provider_network"
		YAML+=$(generate_yaml_entry "$provider_network" "vlan id Unbound" "Failed to get vlan ids for provider-networks.kubeovn.io $provider_network" "error")$'\n'
		continue
	fi

	if [ -z "$provider_network_vlans" ]; then
		log_info "Provider-networks.kubeovn.io $provider_network hasn't spec any vlan id"
		YAML+=$(generate_yaml_entry "$default_interface" "No vlan conflict, but $provider_network hasn't spec any vlan id" "" "")$'\n'
		continue
	fi

	found=false
	for bond in $bonds; do
		if [[ "$default_interface" == "$bond" ]]; then
			log_info "default_interface $default_interface found for provider-network"
			found=true
			log_info "Start checking bond subinterfaces for network card $bond"

			set +e
			log_debug "Start getting all subinterfaces for $bond"
			subinterfaces=$(get_bond_subinterfaces "$bond")
			ret=$?
			log_debug "$(echo "$subinterfaces" | tr '\n' ' ')"
			set -e

			if [ $ret -ne 0 ] || [ -z "$subinterfaces" ]; then
				log_warn "Subinterfaces not found for $bond"
				YAML+=$(generate_yaml_entry "$default_interface" "No Conflict" "" "")$'\n'
			else
				vlan_ids=""
				for subif in $subinterfaces; do
					vlan_id="${subif#*.}"
					vlan_ids+="$vlan_id "
				done
				vlan_ids=${vlan_ids%% }
				log_info "VLAN IDs for $bond: $vlan_ids"

				duplicates=$(comm -12 \
					<(echo "$vlan_ids" | tr ' ' '\n' | sort -n) \
					<(echo "$provider_network_vlans" | tr ' ' '\n' | sort -n) | xargs)

				if [ -n "$duplicates" ]; then
					log_err "Conflict VLAN ID: $duplicates"
					YAML+=$(generate_yaml_entry "$default_interface" "Vlan conflict" "Conflict VLAN ID: $duplicates" "error")$'\n'
				else
					log_info "No conflict vlan id"
					YAML+=$(generate_yaml_entry "$default_interface" "No vlan conflict" "" "")$'\n'
				fi
			fi
			break
		fi
	done
	if [[ "$found" == false ]]; then
		log_err "There is no bond found for provider-networks spec $default_interface"
		YAML+=$(generate_yaml_entry "$default_interface " "Not found" "There is no bond found for provider-networks spec $default_interface" "error")$'\n'
	fi
done

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
