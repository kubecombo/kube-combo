#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start disk IO busy detection"
YAML=$(generate_yaml_detection "disk_busy_results")$'\n'

tmp_yaml=$(mktemp)

# 添加错误处理：如果iostat命令失败才用error
if ! iostat_output=$(iostat -x 1 1 2>/dev/null); then
    log_err "Failed to execute iostat command"
    echo "  - key: \"disk_io_detection\"" >> "$tmp_yaml"
    echo "    value: \"failed\"" >> "$tmp_yaml"
    echo "    err: \"Command execution error\"" >> "$tmp_yaml"
    echo "    level: \"error\"" >> "$tmp_yaml"
else
    echo "$iostat_output" | grep -vE "^avg-cpu|^Device|^$" | while read -r line; do
        disk=$(echo "$line" | awk '{print $1}')
        if echo "$disk" | grep -qE "^nbd|^rbd|^loop|^dm-"; then
            log_debug "Skip non-physical disk: $disk"
            continue
        fi
        util=$(echo "$line" | awk '{print $14}')
        if [[ -z "$util" ]]; then
            continue
        fi
        
        # 修改：业务问题只用info/warning，不用error
        if (($(echo "$util < 70" | bc -l))); then
            level="info"
            err="Normal"
        elif (($(echo "$util < 80" | bc -l))); then
            level="warn"
            err="High"
        elif (($(echo "$util < 90" | bc -l))); then
            level="warn"
            err="Very High"
            log_warn "Disk $disk busy: $util%"
        else
            level="warn"  # 改为warning，不是error
            err="Extremely High"
            log_warn "Disk $disk extremely busy: $util%"  # 改为warn日志
        fi
        
        echo "  - key: \"$disk (%)\"" >> "$tmp_yaml"
        echo "    value: \"$util\"" >> "$tmp_yaml"
        echo "    err: \"$err\"" >> "$tmp_yaml"
        echo "    level: \"$level\"" >> "$tmp_yaml"
    done
fi

YAML+=$(cat "$tmp_yaml")
rm -f "$tmp_yaml"

log_debug "$YAML"
RESULT=$( echo "$YAML" | jinja2 check_disk.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result "$RESULT"