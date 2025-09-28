#!/bin/bash

# 需要挂盘
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start memory size consistency detection"
YAML=$(generate_yaml_detection "memory_size_check_results")$'\n'

current=$(free -g | awk '/Mem:/ {print $2}')
log_debug "Current memory size: ${current}G"
check_result="First record: ${current}G"
err_msg=""

set +x
# 需要挂盘因为pod无状态
last=$(cat /var/log/mem_last_boot_size 2> /dev/null)
#ret=$?
set -x
if [ -z "$last" ]; then
  echo "$current" > /var/log/mem_last_boot_size
  log_info "$check_result"
elif [ "$current" -lt "$last" ]; then
  check_result="Abnormal, current ${current}G is less than last ${last}G"
  err_msg="$check_result"
  log_err "$err_msg"
else
  check_result="Consistent (${current}G)"
  log_info "Memory size check consistent: ${current}G"
fi

YAML+=$(generate_yaml_entry "Consistency" "$check_result" "$err_msg" "")$'\n'

log_debug "$YAML"
# shellcheck disable=SC2154
RESULT=$( echo "$YAML" | jinja2 memory.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result  "$RESULT"