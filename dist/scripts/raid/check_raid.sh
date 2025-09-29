#!/bin/bash
set -e
set -o pipefail

# 目前测试环境只测了storcli64，没有其他raid类型的测试环境

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start RAID health detection"
YAML=$(generate_yaml_detection "raid_health_results")$'\n'

tmp_yaml=$(mktemp)

# 颜色定义（用于控制台输出）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 全局变量
OVERALL_STATUS="HEALTHY"
TOOL=""
TOOL_NAME=""
CONTROLLER_COUNT=0

# 函数：检测RAID相关设备
detect_raid_devices() {
    log_info "检测RAID相关设备"
    local raid_devices=$(lspci | grep -iE 'LSI|MegaRAID|Broadcom / LSI|SAS2|SAS3|RAID_SAS|Adaptec' 2>/dev/null || true)

    if [ -z "$raid_devices" ]; then
        log_warn "本环境不存在RAID卡"
        return 1
    else
        log_info "检测到以下RAID控制器："
        echo "$raid_devices"
        return 0
    fi
}

# 函数：检测适用的工具
detect_tool() {
    log_info "确定适用的检测工具"

    # 测试工具是否有效
    test_tool() {
        local tool=$1
        local tool_name=$2
        local test_cmd=$3
        local count_cmd=$4
        local count_pattern=$5

        if command -v $tool &> /dev/null; then
            log_debug "检测到$tool工具，检查控制器..."
            if eval $test_cmd > /dev/null 2>&1; then
                local count=$(eval $count_cmd 2>/dev/null | grep "$count_pattern" | awk '{print $NF}' | tr -cd '0-9' || echo "0")
                if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
                    TOOL=$tool
                    TOOL_NAME=$tool_name
                    CONTROLLER_COUNT=$count
                    log_info "使用$tool检测到 $count 个控制器"
                    return 0
                else
                    log_debug "$tool未检测到控制器"
                fi
            else
                log_debug "$tool执行失败"
            fi
        else
            log_debug "$tool工具未安装"
        fi
        return 1
    }

    # 优先级1：storcli64
    test_tool "storcli64" "Broadcom/LSI storcli64" \
        "storcli64 show" \
        "storcli64 show" \
        "Number of Controllers"

    # 优先级2：MegaCli64
    if [ -z "$TOOL" ]; then
        test_tool "MegaCli64" "Broadcom/LSI MegaCli64" \
            "MegaCli64 -AdpCount" \
            "MegaCli64 -AdpCount" \
            "Controller Count"
    fi

    # 优先级3：arcconf
    if [ -z "$TOOL" ]; then
        test_tool "arcconf" "Adaptec arcconf" \
            "arcconf list" \
            "arcconf list" \
            "Controllers found"
    fi

    # 优先级4：ssacli
    if [ -z "$TOOL" ]; then
        test_tool "ssacli" "HPE ssacli" \
            "ssacli ctrl all show status" \
            "ssacli ctrl all show status" \
            "Controller Status"
    fi

    if [ -z "$TOOL" ]; then
        log_warn "所有可用工具均未检测到控制器"
        return 1
    fi

    return 0
}

# 函数：使用storcli64检测健康状态
check_with_storcli64() {
    local c=$1
    local controller_key="Controller_$c"
    local value="Normal"
    local err=""
    local level=""

    log_info "检测控制器 $c 状态"

    # 获取控制器信息
    local show_output=$(storcli64 /c$c show 2>/dev/null || echo "command failed")

    if [ "$show_output" = "command failed" ]; then
        value="Abnormal"
        err="控制器$c 通信失败"
        level="warn"
        log_warn "$err"
        echo "  - key: \"$controller_key\"" >> "$tmp_yaml"
        echo "    value: \"$value\"" >> "$tmp_yaml"
        echo "    err: \"$err\"" >> "$tmp_yaml"
        echo "    level: \"$level\"" >> "$tmp_yaml"
        OVERALL_STATUS="CRITICAL"
        return
    fi

    # 检查控制器通信状态
    local ctrl_status=$(echo "$show_output" | grep "Status =" | awk '{print $3}' || echo "Unknown")
    if [ "$ctrl_status" = "Success" ]; then
        err="控制器$c 通信状态正常"
        log_info "$err"
    else
        value="Abnormal"
        err="控制器$c 通信状态异常: $ctrl_status"
        level="warn"
        log_warn "$err"
        OVERALL_STATUS="CRITICAL"
    fi

    # 检查虚拟磁盘状态
    local vd_offline=$(echo "$show_output" | grep -E "^[[:space:]]*[0-9]+/[0-9]+" | grep -c "Offln" || echo "0")
    local vd_degraded=$(echo "$show_output" | grep -E "^[[:space:]]*[0-9]+/[0-9]+" | grep -c "Dgrd\|Pdgd" || echo "0")
    local vd_optimal=$(echo "$show_output" | grep -E "^[[:space:]]*[0-9]+/[0-9]+" | grep -c "Optl" || echo "0")

    # 清理变量，确保只包含数字
    vd_offline=$(echo "$vd_offline" | tr -cd '0-9' || echo "0")
    vd_degraded=$(echo "$vd_degraded" | tr -cd '0-9' || echo "0")
    vd_optimal=$(echo "$vd_optimal" | tr -cd '0-9' || echo "0")

    # 修复：为变量添加引号，防止空值或特殊字符导致的参数过多问题
    if [ "$vd_offline" -gt 0 ]; then
        value="Abnormal"
        err="控制器$c 有 $vd_offline 个虚拟磁盘离线"
        level="error"
        log_error "$err"
        OVERALL_STATUS="CRITICAL"
    elif [ "$vd_degraded" -gt 0 ]; then
        value="Abnormal"
        err="控制器$c 有 $vd_degraded 个虚拟磁盘降级"
        level="error"
        log_error "$err"
        OVERALL_STATUS="CRITICAL"
    elif [ "$vd_optimal" -gt 0 ]; then
        if [ "$value" = "Normal" ]; then
            err="控制器$c 所有虚拟磁盘状态最优（共 $vd_optimal 个）"
            log_info "$err"
        fi
    fi

    # 检查物理磁盘状态
    local pd_failed=$(echo "$show_output" | grep -E "^[[:space:]]*[0-9]+:[0-9]+" | grep -c "Fld\|Fail" || echo "0")
    local pd_rebuilding=$(echo "$show_output" | grep -E "^[[:space:]]*[0-9]+:[0-9]+" | grep -c "Rbld" || echo "0")
    local pd_online=$(echo "$show_output" | grep -E "^[[:space:]]*[0-9]+:[0-9]+" | grep -c "Onln" || echo "0")

    # 清理变量，确保只包含数字
    pd_failed=$(echo "$pd_failed" | tr -cd '0-9' || echo "0")
    pd_rebuilding=$(echo "$pd_rebuilding" | tr -cd '0-9' || echo "0")
    pd_online=$(echo "$pd_online" | tr -cd '0-9' || echo "0")

    # 修复：为变量添加引号，防止空值或特殊字符导致的参数过多问题
    if [ "$pd_failed" -gt 0 ]; then
        value="Abnormal"
        err="控制器$c 有 $pd_failed 个物理磁盘故障"
        level="error"
        log_error "$err"
        OVERALL_STATUS="CRITICAL"
    elif [ "$pd_rebuilding" -gt 0 ]; then
        if [ "$value" = "Normal" ]; then
            value="Warning"
            err="控制器$c 有 $pd_rebuilding 个物理磁盘正在重建"
            level="warn"
            log_warn "$err"
            if [ "$OVERALL_STATUS" = "HEALTHY" ]; then
                OVERALL_STATUS="WARNING"
            fi
        fi
    elif [ "$pd_online" -gt 0 ] && [ "$value" = "Normal" ]; then
        err="控制器$c 所有物理磁盘在线（共 $pd_online 个）"
        log_info "$err"
    fi

    # 检查Cachevault状态
    local cv_status=$(echo "$show_output" | grep "Cachevault" -A2 2>/dev/null | tail -1 | awk '{print $2}' || echo "Unknown")
    if [ "$cv_status" = "Optimal" ]; then
        if [ "$value" = "Normal" ]; then
            err="$err, Cachevault状态最优"
        fi
    elif [ -n "$cv_status" ] && [ "$cv_status" != "Unknown" ]; then
        if [ "$value" = "Normal" ]; then
            value="Warning"
            level="warn"
        fi
        err="$err, Cachevault状态: $cv_status"
        log_warn "控制器$c Cachevault状态: $cv_status"
    fi

    echo "  - key: \"$controller_key\"" >> "$tmp_yaml"
    echo "    value: \"$value\"" >> "$tmp_yaml"
    echo "    err: \"$err\"" >> "$tmp_yaml"
    echo "    level: \"$level\"" >> "$tmp_yaml"
}

# 函数：使用MegaCli64检测健康状态
check_with_megacli64() {
    local a=$1
    local adapter_key="Adapter_$a"
    local value="Normal"
    local err=""
    local level=""

    log_info "检测适配器 $a 状态"

    # 检查适配器信息
    local adapter_info=$(MegaCli64 -AdpAllInfo -a$a 2>/dev/null || echo "command failed")

    if [ "$adapter_info" = "command failed" ]; then
        value="Abnormal"
        err="适配器$a 通信失败"
        level="warn"
        log_warn "$err"
        echo "  - key: \"$adapter_key\"" >> "$tmp_yaml"
        echo "    value: \"$value\"" >> "$tmp_yaml"
        echo "    err: \"$err\"" >> "$tmp_yaml"
        echo "    level: \"$level\"" >> "$tmp_yaml"
        OVERALL_STATUS="CRITICAL"
        return
    fi

    # 检查虚拟磁盘状态
    local vd_info=$(MegaCli64 -LDInfo -Lall -a$a 2>/dev/null || echo "command failed")
    if echo "$vd_info" | grep -q "Degraded"; then
        value="Abnormal"
        err="适配器$a 有虚拟磁盘降级"
        level="error"
        log_error "$err"
        OVERALL_STATUS="CRITICAL"
    elif echo "$vd_info" | grep -q "Optimal"; then
        err="适配器$a 虚拟磁盘状态最优"
        log_info "$err"
    fi

    # 检查物理磁盘状态
    local pd_info=$(MegaCli64 -PDList -a$a 2>/dev/null || echo "command failed")
    if echo "$pd_info" | grep -q "Failed"; then
        value="Abnormal"
        err="适配器$a 有物理磁盘故障"
        level="error"
        log_error "$err"
        OVERALL_STATUS="CRITICAL"
    elif echo "$pd_info" | grep -q "Rebuild"; then
        if [ "$value" = "Normal" ]; then
            value="Warning"
            err="适配器$a 有物理磁盘正在重建"
            level="warn"
            log_warn "$err"
            if [ "$OVERALL_STATUS" = "HEALTHY" ]; then
                OVERALL_STATUS="WARNING"
            fi
        fi
    else
        if [ "$value" = "Normal" ]; then
            err="$err, 物理磁盘状态正常"
        fi
    fi

    echo "  - key: \"$adapter_key\"" >> "$tmp_yaml"
    echo "    value: \"$value\"" >> "$tmp_yaml"
    echo "    err: \"$err\"" >> "$tmp_yaml"
    echo "    level: \"$level\"" >> "$tmp_yaml"
}

# 函数：使用arcconf检测健康状态
check_with_arcconf() {
    local controller_key="Adaptec_Controller"
    local value="Normal"
    local err=""
    local level=""

    log_info "检测Adaptec控制器状态"

    # 检查逻辑设备状态
    local ld_info=$(arcconf getconfig 1 LD 2>/dev/null || echo "command failed")
    if [ "$ld_info" = "command failed" ]; then
        value="Abnormal"
        err="Adaptec控制器通信失败"
        level="warn"
        log_warn "$err"
    elif echo "$ld_info" | grep -q "Degraded"; then
        value="Abnormal"
        err="Adaptec控制器有逻辑设备降级"
        level="error"
        log_error "$err"
        OVERALL_STATUS="CRITICAL"
    elif echo "$ld_info" | grep -q "Optimal"; then
        err="Adaptec控制器逻辑设备状态最优"
        log_info "$err"
    fi

    # 检查物理设备状态
    local pd_info=$(arcconf getconfig 1 PD 2>/dev/null || echo "command failed")
    if [ "$pd_info" != "command failed" ]; then
        if echo "$pd_info" | grep -q "Failed"; then
            value="Abnormal"
            err="$err, 有物理设备故障"
            level="error"
            log_error "Adaptec控制器有物理设备故障"
            OVERALL_STATUS="CRITICAL"
        else
            if [ "$value" = "Normal" ]; then
                err="$err, 物理设备状态正常"
            fi
        fi
    fi

    echo "  - key: \"$controller_key\"" >> "$tmp_yaml"
    echo "    value: \"$value\"" >> "$tmp_yaml"
    echo "    err: \"$err\"" >> "$tmp_yaml"
    echo "    level: \"$level\"" >> "$tmp_yaml"
}

# 函数：使用ssacli检测健康状态
check_with_ssacli() {
    local controller_key="HPE_Controller"
    local value="Normal"
    local err=""
    local level=""

    log_info "检测HPE控制器状态"

    # 检查逻辑卷状态
    local lv_info=$(ssacli ctrl all show config 2>/dev/null || echo "command failed")
    if [ "$lv_info" = "command failed" ]; then
        value="Abnormal"
        err="HPE控制器通信失败"
        level="warn"
        log_warn "$err"
    elif echo "$lv_info" | grep -q "Failed"; then
        value="Abnormal"
        err="HPE控制器有逻辑卷故障"
        level="error"
        log_error "$err"
        OVERALL_STATUS="CRITICAL"
    elif echo "$lv_info" | grep -q "OK"; then
        err="HPE控制器逻辑卷状态正常"
        log_info "$err"
    fi

    echo "  - key: \"$controller_key\"" >> "$tmp_yaml"
    echo "    value: \"$value\"" >> "$tmp_yaml"
    echo "    err: \"$err\"" >> "$tmp_yaml"
    echo "    level: \"$level\"" >> "$tmp_yaml"
}

# 主检测逻辑
main_detection() {
    # 检测RAID设备
    if ! detect_raid_devices; then
        echo "  - key: \"RAID_Detection\"" >> "$tmp_yaml"
        echo "    value: \"Normal\"" >> "$tmp_yaml"
        echo "    err: \"本环境不存在RAID卡\"" >> "$tmp_yaml"
        echo "    level: \"\"" >> "$tmp_yaml"
        return
    fi

    # 检测工具
    if ! detect_tool; then
        echo "  - key: \"RAID_Tool\"" >> "$tmp_yaml"
        echo "    value: \"Abnormal\"" >> "$tmp_yaml"
        echo "    err: \"未找到可用的RAID检测工具\"" >> "$tmp_yaml"
        echo "    level: \"warn\"" >> "$tmp_yaml"
        return
    fi

    # 添加工具检测结果
    echo "  - key: \"RAID_Tool\"" >> "$tmp_yaml"
    echo "    value: \"Normal\"" >> "$tmp_yaml"
    echo "    err: \"使用 $TOOL_NAME 检测到 $CONTROLLER_COUNT 个控制器\"" >> "$tmp_yaml"
    echo "    level: \"\"" >> "$tmp_yaml"

    log_info "使用 $TOOL_NAME 检测RAID健康状态"

    # 根据控制器数量循环检测
    for ((i=0; i<CONTROLLER_COUNT; i++)); do
        case $TOOL in
            "storcli64")
                check_with_storcli64 $i
                ;;
            "MegaCli64")
                check_with_megacli64 $i
                ;;
            "arcconf")
                check_with_arcconf
                break  # arcconf通常只有一个控制器
                ;;
            "ssacli")
                check_with_ssacli
                break  # ssacli通常检测所有控制器
                ;;
        esac
    done

    # 添加总体状态
    local overall_value="Normal"
    local overall_level=""
    case $OVERALL_STATUS in
        "HEALTHY")
            overall_value="Normal"
            overall_level=""
            ;;
        "WARNING")
            overall_value="Warning"
            overall_level="warn"
            ;;
        "CRITICAL")
            overall_value="Abnormal"
            overall_level="error"
            ;;
    esac

    echo "  - key: \"Overall_Status\"" >> "$tmp_yaml"
    echo "    value: \"$overall_value\"" >> "$tmp_yaml"
    echo "    err: \"RAID总体状态: $OVERALL_STATUS\"" >> "$tmp_yaml"
    echo "    level: \"$overall_level\"" >> "$tmp_yaml"
}

# 执行主检测
main_detection

YAML+=$(cat "$tmp_yaml")
rm -f "$tmp_yaml"

log_debug "$YAML"
RESULT=$(echo "$YAML" | jinja2 check_raid.j2 -D NodeName="$Hostname" -D Timestamp="$Timestamp")
log_result "$RESULT"
set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret