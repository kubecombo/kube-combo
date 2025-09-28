#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start SSD SATA mode detection (checking for SATA3 compatibility)"
YAML=$(generate_yaml_detection "ssd_sata_mode_results")$'\n'

tmp_yaml=$(mktemp)
found_sata_ssd=false
smartctl_available=true

# 检查必要工具
if ! command -v smartctl &> /dev/null; then
    log_err "smartctl command not found, SATA mode detection unavailable"
    smartctl_available=false
    echo "  - key: \"sata_mode_detection\"" >> "$tmp_yaml"
    echo "    value: \"tool_missing\"" >> "$tmp_yaml"
    echo "    err: \"smartctl not installed\"" >> "$tmp_yaml"
    echo "    level: \"error\"" >> "$tmp_yaml"
fi

if ! command -v lsblk &> /dev/null; then
    log_err "lsblk command not found, cannot list disks"
    echo "  - key: \"disk_enumeration\"" >> "$tmp_yaml"
    echo "    value: \"failed\"" >> "$tmp_yaml"
    echo "    err: \"lsblk not available\"" >> "$tmp_yaml"
    echo "    level: \"error\"" >> "$tmp_yaml"
    YAML+=$(cat "$tmp_yaml")
    rm -f "$tmp_yaml"
    log_debug "$YAML"
    RESULT=$(echo "$YAML" | jinja2 check_disk.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
    log_result "$RESULT"
    exit 0
fi

# 获取磁盘列表
if ! lsblk_output=$(lsblk -d -o NAME,MODEL,TYPE 2>/dev/null); then
    log_err "Failed to execute lsblk command"
    echo "  - key: \"disk_listing\"" >> "$tmp_yaml"
    echo "    value: \"failed\"" >> "$tmp_yaml"
    echo "    err: \"lsblk execution error\"" >> "$tmp_yaml"
    echo "    level: \"error\"" >> "$tmp_yaml"
else
    echo "$lsblk_output" | grep -v "^NAME" | while read -r disk; do
        disk_name=$(echo "$disk" | awk '{print $1}')
        disk_type=$(echo "$disk" | awk '{print $NF}')
        model=$(echo "$disk" | awk '{$1=$NF=""; print $0}' | sed 's/^[ \t]*//;s/[ \t]*$//')
        
        # 过滤虚拟磁盘和非物理磁盘
        if echo "$disk_name" | grep -qE "^nbd|^rbd|^loop|^dm-|^sr"; then
            log_debug "Skip virtual disk: $disk_name"
            continue
        fi
        
        # 只处理物理磁盘
        if [[ "$disk_type" != "disk" ]]; then
            log_debug "Skip non-disk device: $disk_name (type: $disk_type)"
            continue
        fi
        
        # 检查是否为SSD
        rotational_file="/sys/block/$disk_name/queue/rotational"
        if [[ ! -f "$rotational_file" ]]; then
            log_debug "Skip $disk_name: rotational file not found"
            continue
        fi
        
        rotational=$(cat "$rotational_file" 2>/dev/null || echo "1")
        if [[ "$rotational" -ne 0 ]]; then
            log_debug "Skip HDD: $disk_name"
            continue
        fi
        
        # 只关注SATA SSD，不处理NVMe等
        mode="Unknown"
        level="info"
        err="检测正常"
        interface_type="Unknown"
        sata_version=""
        
        if [[ "$smartctl_available" == "true" ]]; then
            if ! interface_info=$(sudo smartctl -i "/dev/$disk_name" 2>/dev/null); then
                log_warn "Failed to read interface info for $disk_name"
                err="SMART信息读取失败"
                level="warn"
            else
                # 检测接口类型
                if echo "$interface_info" | grep -qi "SATA"; then
                    interface_type="SATA"
                    found_sata_ssd=true
                    
                    # 提取SATA版本信息
                    if echo "$interface_info" | grep -q "SATA Version"; then
                        sata_version=$(echo "$interface_info" | grep "SATA Version" | awk -F: '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//')
                        mode="$sata_version"
                        
                        # 核心检测逻辑：判断是否为SATA3模式
                        if echo "$sata_version" | grep -qE "3\.|SATA 6.0|6\.0 Gbps|6\.0Gb/s"; then
                            err="$model - SATA3模式（6 Gbps）- 正常"
                            level="info"
                            log_info "SATA SSD $disk_name 运行在SATA3模式: $sata_version"
                            
                        elif echo "$sata_version" | grep -qE "2\.|SATA 3.0|3\.0 Gbps|3\.0Gb/s"; then
                            err="$model - SATA2模式（3 Gbps）- 性能受限"
                            level="error"  # 重点告警！
                            log_err "SATA SSD $disk_name 运行在SATA2模式: $sata_version - 无法发挥SSD性能"
                            
                        elif echo "$sata_version" | grep -qE "1\.|SATA 1.5|1\.5 Gbps|1\.5Gb/s"; then
                            err="$model - SATA1模式（1.5 Gbps）- 严重性能问题"
                            level="error"
                            log_err "SATA SSD $disk_name 运行在SATA1模式: $sata_version - 严重性能瓶颈"
                            
                        else
                            err="$model - SATA模式未知 - 需要手动确认"
                            level="warn"
                            log_warn "SATA SSD $disk_name 模式未知: $sata_version"
                        fi
                    else
                        err="$model - SATA版本信息缺失"
                        level="warn"
                        log_warn "SATA SSD $disk_name 无法获取版本信息"
                    fi
                    
                elif echo "$interface_info" | grep -qi "NVMe"; then
                    interface_type="NVMe"
                    mode="NVMe"
                    err="NVMe设备（无需SATA模式检测）"
                    level="info"
                    log_debug "NVMe SSD $disk_name 跳过SATA模式检测"
                    continue  # 跳过NVMe设备
                    
                else
                    interface_type="Other"
                    err="非SATA接口设备"
                    level="info"
                    log_debug "非SATA设备 $disk_name 跳过检测"
                    continue  # 跳过非SATA设备
                fi
            fi
        else
            err="检测工具不可用"
            level="warn"
        fi
        
        # 只输出SATA SSD的检测结果
        if [[ "$interface_type" == "SATA" ]]; then
            echo "  - key: \"$disk_name\"" >> "$tmp_yaml"
            echo "    value: \"$mode\"" >> "$tmp_yaml"
            echo "    err: \"$err\"" >> "$tmp_yaml"
            echo "    level: \"$level\"" >> "$tmp_yaml"
        fi
    done
fi

# 如果没有找到SATA SSD，添加提示信息
if [[ "$found_sata_ssd" != "true" ]]; then
    echo "  - key: \"sata_ssd_detection\"" >> "$tmp_yaml"
    echo "    value: \"no_sata_ssd_found\"" >> "$tmp_yaml"
    echo "    err: \"未检测到SATA SSD设备\"" >> "$tmp_yaml"
    echo "    level: \"info\"" >> "$tmp_yaml"
fi

YAML+=$(cat "$tmp_yaml")
rm -f "$tmp_yaml"

log_debug "$YAML"
RESULT=$(echo "$YAML" | jinja2 check_disk.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result "$RESULT"