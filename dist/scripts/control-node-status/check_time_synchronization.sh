#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start time synchronization detection"
YAML=$(generate_yaml_detection "time_synchronization_results")$'\n'

tmp_yaml=$(mktemp)

current_node=$(echo "$(hostname -s)" | tr '[:upper:]' '[:lower:]')

# Check chronyd service status
status=$(systemctl is-active chronyd 2>/dev/null || echo "unknown")

if [ "$status" != "active" ]; then
    value="Abnormal"
    err="Chronyd service is not active (current status: $status)"
    level="warn"
    log_warn "Node $current_node time synchronization detection failed: $err"
else
    # Get time offset
    offset_str=$(chronyc tracking 2>/dev/null | awk '/^System time/ {print $4}' || echo "")
    
    if [ -z "$offset_str" ]; then
        value="Abnormal"
        err="Failed to get time offset from chronyc tracking"
        level="warn"
        log_warn "Node $current_node time synchronization detection failed: $err"
    else
        # Use awk for floating point comparison
        offset_compare=$(echo "$offset_str" | awk '{if ($1 > 15) print "high"; else if ($1 < -15) print "low"; else print "normal"}')
        
        if [ "$offset_compare" != "normal" ]; then
            value="Abnormal"
            err="Time offset is greater than 15 s ($offset_str s)"
            level="warn"
            log_warn "Node $current_node time synchronization abnormal, offset $offset_str seconds: $err"
        else
            value="Normal"
            err="Offset less than or equal to 15 s ($offset_str s)"
            level="info"
            log_info "Node $current_node time synchronization normal, offset $offset_str seconds"
        fi
    fi
fi

echo "  - key: \"$current_node\"" >> "$tmp_yaml"
echo "    value: \"$value\"" >> "$tmp_yaml"
echo "    err: \"$err\"" >> "$tmp_yaml"
echo "    level: \"$level\"" >> "$tmp_yaml"

YAML+=$(cat "$tmp_yaml")
rm -f "$tmp_yaml"

log_debug "$YAML"
RESULT=$(echo "$YAML" | jinja2 check_control.j2 -D NodeName="$Hostname" -D Timestamp="$Timestamp")
log_result "$RESULT"