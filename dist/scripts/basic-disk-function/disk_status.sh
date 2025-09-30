#!/bin/bash
set -e
set -o pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start disk status detection"
YAML=$(generate_yaml_detection "disk_status_results")$'\n'

tmp_yaml=$(mktemp)

# 方法1：检查磁盘是否可读写（更可靠）
check_disk_status() {
    local disk_name=$1
    local model=$2

    # 检查1：设备文件是否存在
    if ! nsenter -t 1 -m -u -i -n test -b "/dev/$disk_name"; then
        echo "offline"
        return
    fi

    # 检查2：尝试读取设备信息（非破坏性）
    if nsenter -t 1 -m -u -i -n smartctl --info "/dev/$disk_name" &>/dev/null; then
        echo "online"
    elif nsenter -t 1 -m -u -i -n dd if="/dev/$disk_name" of=/dev/null bs=512 count=1 status=none &>/dev/null; then
        echo "online"
    elif nsenter -t 1 -m -u -i -n test -d "/sys/block/$disk_name"; then
        # 检查3：sysfs状态
        local removable=$(nsenter -t 1 -m -u -i -n cat "/sys/block/$disk_name/removable" 2>/dev/null || echo "1")
        if [ "$removable" = "0" ]; then
            echo "online"
        else
            echo "unknown"
        fi
    else
        echo "offline"
    fi
}

# 使用 nsenter 执行 lsblk 获取磁盘信息
nsenter -t 1 -m -u -i -n lsblk -d -o NAME,MODEL,SIZE | grep -v "^NAME" | while read -r disk; do
    disk_name=$(echo "$disk" | awk '{print $1}')

    # 过滤虚拟磁盘
    if echo "$disk_name" | grep -qE "^nbd|^rbd|^loop|^dm-|^sr"; then
        log_debug "Skip non-physical disk: $disk_name"
        continue
    fi

    model=$(echo "$disk" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')

    # 使用更可靠的状态检测
    status=$(check_disk_status "$disk_name" "$model")

    case "$status" in
        "online")
            level=""
            ;;
        "offline")
            level="error"
            log_err "Disk $disk_name is offline"
            ;;
        "unknown")
            level="warn"
            log_warn "Disk $disk_name status unknown"
            ;;
        *)
            level="warn"
            status="unknown"
            ;;
    esac

    echo "  - key: \"$disk_name\"" >> "$tmp_yaml"
    echo "    value: \"$model\"" >> "$tmp_yaml"
    echo "    err: \"$status\"" >> "$tmp_yaml"
    echo "    level: \"$level\"" >> "$tmp_yaml"
done

YAML+=$(cat "$tmp_yaml")
rm -f "$tmp_yaml"

log_debug "$YAML"
RESULT=$(echo "$YAML" | jinja2 check_disk.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result "$RESULT"
set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret