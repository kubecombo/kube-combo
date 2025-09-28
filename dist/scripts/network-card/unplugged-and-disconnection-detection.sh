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

log_info "Start network card unplugged and disconnection detection"
YAML=$(generate_yaml_detection "unplugged_and_disconnection_results")$'\n'

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

	log_debug "Get Link detected status for $bond"
	link_status=$(ethtool "$bond" 2>/dev/null | grep "Link detected:" | awk '{print $3}')
	link_status=${link_status:-Unknown}

	case "$link_status" in
		yes)
			all_yes=true
			for slave in $slaves; do
				log_debug "Get Link detected status for $slave"
				slave_link_status=$(ethtool "$slave" 2>/dev/null | grep "Link detected:" | awk '{print $3}')
				slave_link_status=${slave_link_status:-Unknown}
				case "$slave_link_status" in
					yes)
						# continue to next slave
						;;
					no)
						log_err "$slave is running on Link detected: no"
						YAML+=$(generate_yaml_entry "$bond" "Slave interface Link detected: no" "Slave interface $slave is running on Link detected: no" "error")$'\n'
						all_yes=false
						break
						;;
					Unknown | *)
						log_warn "$slave is running on Link detected: Unknown"
						YAML+=$(generate_yaml_entry "$bond" "Slave interface Link detected status Unknown" "Slave interface $slave is running on Unknown Link detected status" "warn")$'\n'
						all_yes=false
						break
						;;
				esac
			done
			if [ "$all_yes" = true ]; then
				log_info "$bond and all its slaves are running on Link detected: yes"
				YAML+=$(generate_yaml_entry "$bond" "Link detected" "" "")$'\n'
			fi
			;;
		no)
			log_err "$bond Link detected is no"
			YAML+=$(generate_yaml_entry "$bond" "Link detected status is no" "The $bond link status is disconnected" "warn")$'\n'
			;;
		Unknown | *)
			log_err "$bond Link detected is Unknown"
			YAML+=$(generate_yaml_entry "$bond" "Link detected status is Unknown" "The bond network card's link status is unknown" "warn")$'\n'
			;;
	esac
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
