#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start disk IO utilization detection"

# 生成YAML头部
YAML=$(generate_yaml_detection "disk_busy_results")$'\n'

# 在Pod中运行节点命令
run_on_node() {
    nsenter -t 1 -m -u -i -n "$@"
}

# 获取物理磁盘列表（排除虚拟设备和网络设备）
get_physical_disks() {
    # 使用lsblk排除loop、ram、fd、dm、nbd设备
    if run_on_node command -v lsblk &> /dev/null; then
        run_on_node lsblk -d -o NAME,TYPE | awk '$2=="disk" && $1 !~ /^nbd/ {print $1}'
    else
        # 如果lsblk不可用，直接从/sys/block获取并过滤
        run_on_node find /sys/block -type l \( -name "sd*" -o -name "hd*" -o -name "vd*" -o -name "nvme*" \) ! -name "nbd*" 2>/dev/null | \
            xargs -I {} basename {} | sort
    fi
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    if ! run_on_node command -v iostat &> /dev/null; then
        missing_deps+=("sysstat")
    fi
    
    if ! run_on_node command -v bc &> /dev/null; then
        missing_deps+=("bc")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "Missing dependencies: ${missing_deps[*]}"
        YAML+=$(generate_yaml_entry "disk_io_utilization" "N/A" "Missing dependencies: ${missing_deps[*]}" "error")$'\n'
        return 1
    fi
    return 0
}

# 格式化数字，确保小数点前有0
format_number() {
    local num=$1
    if [[ $num == .* ]]; then
        echo "0$num"
    else
        echo "$num"
    fi
}

# 根据IO利用率确定level
get_io_level() {
    local utilization=$1
    if (( $(echo "$utilization > 90" | bc -l) )); then
        echo "error"
    elif (( $(echo "$utilization >= 80" | bc -l) )); then
        echo "warn"
    else
        echo ""
    fi
}

# 主检测逻辑
detect_disk_io() {
    local disks
    disks=$(get_physical_disks)
    
    if [ -z "$disks" ]; then
        log_warn "No physical disks found"
        YAML+=$(generate_yaml_entry "disk_io_utilization" "N/A" "No physical disks detected" "warn")$'\n'
        return
    fi
    
    log_debug "Detected physical disks: $(echo $disks | tr '\n' ' ')"
    
    # 执行iostat收集数据
    log_debug "Run: nsenter -t 1 -m -u -i -n iostat -x 2 5"
    local iostat_output
    iostat_output=$(run_on_node iostat -x 2 5 2>/dev/null || {
        log_warn "iostat command failed"
        YAML+=$(generate_yaml_entry "disk_io_utilization" "N/A" "iostat command execution failed" "error")$'\n'
        return
    })
    
    local found_data=0
    
    for disk in $disks; do
        local util_sum=0
        local count=0
        local util_values=()
        
        # 提取该磁盘的IO利用率数据
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                local util
                util=$(echo "$line" | awk '{print $NF}')
                
                # 检查是否为数字
                if [[ $util =~ ^[0-9]+([.][0-9]+)?$ ]]; then
                    util=$(format_number "$util")
                    util_sum=$(echo "$util_sum + $util" | bc -l)
                    util_values+=("$util")
                    count=$((count + 1))
                fi
            fi
        done < <(echo "$iostat_output" | grep "^$disk ")
        
        if [ $count -gt 0 ]; then
            found_data=1
            local average
            average=$(echo "scale=2; $util_sum / $count" | bc -l)
            average=$(format_number "$average")
            
            local level
            level=$(get_io_level "$average")
            
            local err_msg=""
            if [ -n "$level" ]; then
                if [ "$level" = "error" ]; then
                    err_msg="IO utilization too high"
                elif [ "$level" = "warn" ]; then
                    err_msg="IO utilization high"
                fi
            fi
            
            log_debug "Disk $disk: average IO utilization = ${average}%, level = $level"
            YAML+=$(generate_yaml_entry "$disk" "${average}%" "$err_msg" "$level")$'\n'
        else
            log_debug "Disk $disk: no IO data available"
            YAML+=$(generate_yaml_entry "$disk" "N/A" "No IO utilization data" "warn")$'\n'
        fi
    done
    
    if [ $found_data -eq 0 ]; then
        log_warn "No IO utilization data collected for any disk"
        YAML+=$(generate_yaml_entry "disk_io_utilization" "N/A" "Failed to collect IO utilization data" "error")$'\n'
    fi
}

# 执行检测
if check_dependencies; then
    detect_disk_io
fi

log_debug "Disk IO utilization YAML:"
log_debug "$YAML"

# 渲染结果
# shellcheck disable=SC2154
RESULT=$(echo "$YAML" | jinja2 "$(dirname "${BASH_SOURCE[0]}")/check_disk.j2" -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result "$RESULT"

# 发送结果
set +e
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret