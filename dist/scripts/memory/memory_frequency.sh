#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start memory frequency detection"
YAML=$(generate_yaml_detection "memory_frequency_results")$'\n'

# 检查内存频率
log_debug "Start: dmidecode -t memory"
dmidecode -t memory | awk -F: '
  /Locator/ {slot=$2; gsub(/^[ \t]+/, "", slot)}
  /Speed:/ && !/Configured/ {
    freq=$2; gsub(/^[ \t]+/, "", freq)
    if (freq != "Unknown" && freq != "") {
      if (slot == "") slot = "N/A"
      printf "  - key: %s\n    value: %s\n    err: \"\"\n", slot, freq
    }
  }' >> temp.yaml

if [ ! -s temp.yaml ]; then
  YAML+=$(generate_yaml_entry "memory" "Unknown" "No memory frequency info found" "error")$'\n'
else
  YAML+=$(cat temp.yaml)$'\n'
fi
rm -f temp.yaml

log_debug "$YAML"
# shellcheck disable=SC2154
RESULT=$( echo "$YAML" | jinja2 memory.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result  "$RESULT"
