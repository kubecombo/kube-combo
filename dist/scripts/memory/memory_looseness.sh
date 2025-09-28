#!/bin/bash

# 不好实现
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start memory looseness detection"
YAML=$(generate_yaml_detection "memory_loose_results")$'\n'

log_debug "Check file: /var/log/mem_loose.log"
status="Normal"
err_msg=""
if [ -s /var/log/mem_loose.log ]; then
  status="Abnormal"
  err_msg="Looseness detected, please check /var/log/mem_loose.log"
  log_warn "$err_msg"
else
  log_info "Memory looseness check normal"
fi

YAML+=$(generate_yaml_entry "Status" "$status" "$err_msg" "")$'\n'

log_debug "$YAML"
# shellcheck disable=SC2154
RESULT=$( echo "$YAML" | jinja2 memory.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result  "$RESULT"