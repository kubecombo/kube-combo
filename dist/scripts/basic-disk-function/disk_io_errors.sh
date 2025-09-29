#!/bin/bash
set -e
set -o pipefail

# 有问题
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start disk IO error detection"
YAML=$(generate_yaml_detection "io_errors_results")$'\n'

tmp_yaml=$(mktemp)
disk_found=false

while read -r line; do
  disk=$(echo "$line" | awk '{print $3}')
  if echo "$disk" | grep -qE "^nbd|^rbd|^loop|^dm-"; then
    continue
  fi
  disk_found=true
  read_errors=$(echo "$line" | awk '{print $4}')
  write_errors=$(echo "$line" | awk '{print $8}')
  dmesg_errors=$(dmesg | tail -n 1000 | grep -i "$disk.*error" | wc -l)
  level=""
  err="Normal"
  if [ "$read_errors" -gt 0 ] || [ "$write_errors" -gt 0 ] || [ "$dmesg_errors" -gt 0 ]; then
    level="error"
    err="读: $read_errors, 写: $write_errors, 日志: $dmesg_errors"
    log_err "Disk $disk IO error detected"
  fi
  echo "  - key: \"$disk\"" >> "$tmp_yaml"
  echo "    value: \"$level\"" >> "$tmp_yaml"
  echo "    err: \"$err\"" >> "$tmp_yaml"
  echo "    level: \"$level\"" >> "$tmp_yaml"
done < /proc/diskstats

if ! grep -q "key:" "$tmp_yaml"; then
  echo "  - key: \"no_disk_found\"" >> "$tmp_yaml"
  echo "    value: \"none\"" >> "$tmp_yaml"
  echo "    err: \"No disk found in /proc/diskstats\"" >> "$tmp_yaml"
  echo "    level: \"\"" >> "$tmp_yaml"
fi

YAML+=$(cat "$tmp_yaml")
rm -f "$tmp_yaml"

log_debug "$YAML"
RESULT=$( echo "$YAML" | jinja2 check_disk.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result  "$RESULT"
set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret