#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")"'/../util/util.sh'
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start disk usage detection"
YAML=$(generate_yaml_detection "disk_usage_results")$'\n'

tmp_yaml=$(mktemp)
df -hT -x tmpfs -x devtmpfs | awk 'NR>1' | while read -r line; do
  fs=$(echo "$line" | awk '{print $1}')
  type=$(echo "$line" | awk '{print $2}')
  size=$(echo "$line" | awk '{print $3}')
  used=$(echo "$line" | awk '{print $4}')
  avail=$(echo "$line" | awk '{print $5}')
  usep=$(echo "$line" | awk '{print $6}' | tr -d '%')
  mount=$(echo "$line" | awk '{print $7}')
  level=""
  err="Normal"
  if [ "$usep" -ge 90 ]; then
    level="error"
    err="Usage is extremely high, please expand or clean up."
    log_err "Disk $fs ($mount) usage $usep% is extremely high"
  elif [ "$usep" -ge 80 ]; then
    level="warn"
    err="Usage is high, please monitor."
    log_warn "Disk $fs ($mount) usage $usep% is high"
  fi
  echo "  - key: \"$fs ($mount)\"" >> "$tmp_yaml"
  echo "    value: \"$usep% ($used/$size)\"" >> "$tmp_yaml"
  echo "    err: \"$err\"" >> "$tmp_yaml"
  echo "    level: \"$level\"" >> "$tmp_yaml"
done

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