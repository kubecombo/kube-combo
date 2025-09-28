#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start memory vendor detection"
YAML=$(generate_yaml_detection "memory_vendor_results")$'\n'

log_debug "Run: sudo dmidecode -t memory"
sudo dmidecode -t memory | awk -F: '
  /Locator/ {slot=$2; gsub(/^[ \t]+/, "", slot)}
  /Manufacturer/ {
    vendor=$2; gsub(/^[ \t]+/, "", vendor)
    if (vendor ~ /[A-Za-z]/) {
      if (slot == "") slot = "N/A"
      printf "  - key: %s\n    value: %s\n    err: \"\"\n", slot, vendor
    }
  }' >> temp.yaml

if [ ! -s temp.yaml ]; then
  YAML+=$(generate_yaml_entry "memory" "Unknown" "No memory vendor info found" "error")$'\n'
else
  YAML+=$(cat temp.yaml)$'\n'
fi
rm -f temp.yaml

log_debug "$YAML"
# shellcheck disable=SC2154
RESULT=$( echo "$YAML" | jinja2 memory.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result  "$RESULT"