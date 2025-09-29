#!/bin/bash
set -e
set -o pipefail
#set -x  # 开启执行追踪

# 引入工具脚本
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/cpu.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"



# 初始化目录与环境变量
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit
SAMPLE_INTERVAL=0.1  # 采样间隔（秒）

# 启动日志
log_info "Start CPU usage detection [Node: ${NodeName}]"
# 初始化YAML结果集
log_info "Initialize YAML result set"
YAML=$(generate_yaml_detection "cpu_usage_results")$'\n'
log_debug "YAML initialization completed, initial content: [$YAML]"

# 核心函数：计算物理CPU使用率
calc_physical_cpu_usage() {
    local phys_id=$1
    local cores=$2
    local user1=0 nice1=0 system1=0 idle1=0
    local user2=0 nice2=0 system2=0 idle2=0
    log_debug "[CPU${phys_id}] Start calculating usage (cores: $cores)" >&2

    # 第一次采样
    for core in $cores; do
        if ! read -r u n s i <<< $(grep "cpu$core" /proc/stat 2>/dev/null | awk '{print $2, $3, $4, $5}'); then
            log_err "[CPU${phys_id}] Core $core first sampling failed" >&2
            echo "error"
            return 1
        fi
        user1=$((user1 + u))
        nice1=$((nice1 + n))
        system1=$((system1 + s))
        idle1=$((idle1 + i))
    done
    log_debug "[CPU${phys_id}] First sampling: user=$user1, nice=$nice1, system=$system1, idle=$idle1" >&2
    sleep $SAMPLE_INTERVAL

    # 第二次采样
    for core in $cores; do
        if ! read -r u n s i <<< $(grep "cpu$core" /proc/stat 2>/dev/null | awk '{print $2, $3, $4, $5}'); then
            log_err "[CPU${phys_id}] Core $core second sampling failed" >&2
            echo "error"
            return 1
        fi
        user2=$((user2 + u))
        nice2=$((nice2 + n))
        system2=$((system2 + s))
        idle2=$((idle2 + i))
    done
    log_debug "[CPU${phys_id}] Second sampling: user=$user2, nice=$nice2, system=$system2, idle=$idle2" >&2

    # 计算使用率
    local total_diff=$(( (user2-user1) + (nice2-nice1) + (system2-system1) + (idle2-idle1) ))
    local usage=0
    [ $total_diff -ne 0 ] && usage=$(( (total_diff - (idle2-idle1)) * 100 / total_diff ))
    log_debug "[CPU${phys_id}] Calculation: total_diff=$total_diff, idle_diff=$((idle2-idle1)), usage=$usage%" >&2
    log_info "[CPU${phys_id}] Usage rate: $usage%" >&2
    echo "$usage"
    return 0
}

# 核心逻辑：识别物理CPU及核心映射
log_info "Start identifying physical CPUs and core mapping"

# 提取physical ids
log_debug "Extract physical ids from /proc/cpuinfo"
physical_ids=$(
    grep '^physical id' /proc/cpuinfo 2>/dev/null |
    awk '{print $4}' |
    sort -n |
    uniq |
    tr '\n' ' ' |
    tr -d '\r' |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
)
ret=$?
log_debug "Physical ids extraction result: [$physical_ids], ret=$ret"
physical_ids_arr=($physical_ids)
phys_cpu_count=${#physical_ids_arr[@]}

# 验证识别结果
log_info "Physical CPU identification: Count=${phys_cpu_count}, List=[${physical_ids_arr[@]}]"

if [ $ret -ne 0 ] || [ $phys_cpu_count -eq 0 ]; then
    log_err "No physical CPUs identified"
    YAML+=$(generate_yaml_entry "PhysicalCPU_Overall" "Unknown" "No physical CPU info" "error")$'\n'
else
    log_info "${phys_cpu_count} physical CPUs identified"
    declare -A phys_core_map  # 关联数组

    # 构建核心映射
    log_info "Start building core mapping (total ${phys_cpu_count} CPUs)"
    for phys_id in "${physical_ids_arr[@]}"; do
        log_info "Process CPU$phys_id → Extract core list"
        core_list=$(awk -v target_pid="$phys_id" '
            /^physical id/ { current_pid = $4; is_target = (current_pid == target_pid) ? 1 : 0; }
            is_target && /^processor/ { print $3; }
        ' /proc/cpuinfo 2>/dev/null | tr '\n' ' ')
        log_debug "CPU$phys_id core list: [$core_list]"
        if [ -z "$core_list" ]; then
            log_warn "CPU$phys_id core list is empty, marked as unknown"
            core_list="unknown"
        fi
        phys_core_map[$phys_id]="$core_list"
        log_info "CPU$phys_id core mapping done (core count: $(echo $core_list | wc -w))"
    done
    log_info "Core mapping construction completed"

    # 计算每个CPU的使用率
    log_info "Start calculating usage rates (total ${phys_cpu_count} CPUs)"
    for phys_id in "${physical_ids_arr[@]}"; do
        cores=${phys_core_map[$phys_id]}
        log_info "Calculate CPU$phys_id (core count: $(echo $cores | wc -w))"
        usage=$(calc_physical_cpu_usage "$phys_id" "$cores")
        log_debug "CPU$phys_id calculation result: [$usage]"
        if [ "$usage" = "error" ]; then
            YAML+=$(generate_yaml_entry "PhysicalCPU$phys_id" "Unknown" "Sampling failed" "error")$'\n'
        else
            level=""
            err=""
            if [ $usage -ge 90 ]; then
                level="warn"
                err="CPU usage too high (≥90% threshold)"
                log_warn "$err: CPU$phys_id = $usage%"
            fi
            YAML+=$(generate_yaml_entry "PhysicalCPU$phys_id" "$usage%" "$err" "$level")$'\n'
            log_info "CPU$phys_id YAML entry appended"
        fi
    done
    log_info "All CPU usage calculations completed"
fi

# 输出YAML
log_info "Output final YAML result"
log_info "=== YAML Content Start ==="
log_info "$YAML"
log_info "=== YAML Content End ==="
log_info "CPU usage detection completed"
RESULT=$( echo "$YAML" | jinja2 cpu_detect.j2 --format=yaml -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result  "$RESULT"

#向eis的后端服务发送post请求，上报检测结果
set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret