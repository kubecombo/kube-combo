#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start memory read/write performance detection"
YAML=$(generate_yaml_detection "memory_rw_perf_results")$'\n'

log_debug "Run: dd if=/dev/zero of=/tmp/testfile bs=1M count=256 conv=fdatasync"
dd_output=$(dd if=/dev/zero of=/tmp/testfile bs=1M count=256 conv=fdatasync 2>&1)
speed=$(echo "$dd_output" | grep copied | awk '{print $(NF-1)}')
speed_unit=$(echo "$dd_output" | grep copied | awk '{print $NF}')
rm -f /tmp/testfile

YAML+=$(generate_yaml_entry "Performance" "${speed} ${speed_unit}" "" "")$'\n'

log_debug "Memory read/write performance: $speed $speed_unit"
log_debug "$YAML"
# shellcheck disable=SC2154
RESULT=$( echo "$YAML" | jinja2 memory.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result  "$RESULT"