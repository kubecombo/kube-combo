#!/bin/bash
set -e
set -o pipefail

#有问题

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start SSD lifetime detection"
YAML=$(generate_yaml_detection "ssd_lifetime_results")$'\n'

tmp_yaml=$(mktemp)
lsblk -d -o NAME,MODEL | grep -v "^NAME" | while read -r disk; do
  disk_name=$(echo "$disk" | awk '{print $1}')
  if echo "$disk_name" | grep -qE "^nbd|^rbd|^loop|^dm-"; then
    continue
  fi
  # 只检测SSD
  if [ ! -f "/sys/block/$disk_name/queue/rotational" ] || [ "$(cat /sys/block/"$disk_name"/queue/rotational 2>/dev/null)" -ne 0 ]; then
    continue
  fi
  remaining="Unknown"
  level="info"
  err="Normal"
  lifetime_output=$(sudo smartctl -a "/dev/$disk_name" 2>/dev/null)
  if echo "$lifetime_output" | grep -q "Percentage Used"; then
    used=$(echo "$lifetime_output" | grep "Percentage Used" | awk '{print $3}')
    remaining=$((100 - used))
  elif echo "$lifetime_output" | grep -q "Remaining Life"; then
    remaining=$(echo "$lifetime_output" | grep "Remaining Life" | awk '{print $4}' | sed 's/%//')
  fi
  if [[ "$remaining" != "Unknown" && "$remaining" -lt 20 ]]; then
    level="error"
    err="寿命不足，建议更换"
    log_err "SSD $disk_name 剩余寿命低: $remaining%"
  fi
  echo "  - key: \"$disk_name\"" >> "$tmp_yaml"
  echo "    value: \"$remaining%\"" >> "$tmp_yaml"
  echo "    err: \"$err\"" >> "$tmp_yaml"
  echo "    level: \"$level\"" >> "$tmp_yaml"
done

YAML+=$(cat "$tmp_yaml")
rm -f "$tmp_yaml"

log_debug "$YAML"
RESULT=$( echo "$YAML" | jinja2 check_disk.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result  "$RESULT"