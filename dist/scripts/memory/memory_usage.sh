#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start memory usage detection"
YAML=$(generate_yaml_detection "memory_usage_results")$'\n'

usage=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
if [ "$usage" -gt 80 ]; then
  level="warn"
  err_msg="Memory usage is high"
  log_info "Memory usage: ${usage}% ($level)"
else
  level=""
  err_msg="Memory usage is normal"
  log_err "Memory usage: ${usage}% ($level)"
fi

YAML+=$(generate_yaml_entry "Usage" "${usage}%" "$err_msg" "")$'\n'

log_debug "$YAML"
# shellcheck disable=SC2154
RESULT=$( echo "$YAML" | jinja2 memory.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result  "$RESULT"
set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret