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
	response=$(send_post "asdas" "$RESULT" admin)
	# response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
	ret=$?
	log_debug "$(echo "$response" | tr '\n' ' ')"
	set -e

	exit $ret
fi
