#!/bin/bash
set -e
set -o pipefail

# 引入工具脚本
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/cpu.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"


# ==============================================
# 初始化环境变量
# ==============================================
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

# 核心变量定义
PROM_NAMESPACE="monitoring"                  # Prometheus所在K8s命名空间
PROM_SERVICE="cmss-ekiplus-prometheus-system"  # Prometheus的K8s Service名称
PROM_PORT="9090"                             # Prometheus默认端口（固定值）
ALERT_RULE_NAME="CPUFrequencyHigh"           # 目标CPU频率告警规则名称
declare -A ALERT_INFO_MAP                    # 存储「cpuXX→告警描述」的关联数组


# ==============================================
# 启动日志与YAML结果集初始化
# ==============================================
log_info "Start CPU frequency detection process"
# 初始化YAML根节点
YAML=$(generate_yaml_detection "cpu_frequency_results")$'\n'
# 截断长内容预览，避免日志冗余
log_debug "Initialized YAML result set (preview): ${YAML:0:50}..."


# ==============================================
# 步骤1：获取K8s节点Instance标识
# ==============================================
log_info "Retrieving K8s Instance for node: ${NodeName}"

# 临时关闭set -e，避免工具函数非0返回中断脚本
set +e
log_debug "Calling utility function: get_k8s_instance(${NodeName})"
INSTANCE=$(get_k8s_instance "$NodeName")
ret=$?
log_debug "Instance query result: '$INSTANCE', return code: ${ret}"
# 恢复set -e
set -e

# 校验Instance有效性
if [ $ret -ne 0 ] || [ -z "$INSTANCE" ]; then
    log_err "Failed to get K8s Instance (return code: ${ret}, result: '$INSTANCE')"
    # 调用util中定义的generate_yaml_entry生成错误条目
    YAML+=$(generate_yaml_entry "CPU_Freq_Instance" "Unknown" "Instance get failed" "error")$'\n'
    exit 0
fi
log_info "Successfully obtained K8s Instance: ${INSTANCE}"


# ==============================================
# 步骤2：构建Prometheus Service URL并验证可达性
# ==============================================
log_info "Start building Prometheus Service access URL"

# K8s集群内Service标准访问格式：http://服务名.命名空间.svc.cluster.local:端口
PROM_URL="http://${PROM_SERVICE}.${PROM_NAMESPACE}.svc.cluster.local:${PROM_PORT}"
log_debug "Built Prometheus Service URL: ${PROM_URL}"

# 验证Prometheus服务可达性（超时5秒，避免长期阻塞）
set +e
log_debug "Checking Prometheus connectivity: ${PROM_URL}/-/healthy (timeout: 5s)"
curl -s --connect-timeout 5 "${PROM_URL}/-/healthy" >/dev/null
ret=$?
set -e

# 处理服务不可达场景
if [ $ret -ne 0 ]; then
    log_err "Prometheus Service unreachable (URL: ${PROM_URL}, return code: ${ret})"
    # 调用util中定义的generate_yaml_entry生成错误条目
    YAML+=$(generate_yaml_entry "CPU_Freq_Prometheus" "Unknown" "Prometheus Service unreachable" "error")$'\n'
    exit 0
fi
log_info "Prometheus connection verified - Instance: ${INSTANCE}, URL: ${PROM_URL}, Alert Rule: ${ALERT_RULE_NAME}"


# ==============================================
# 核心逻辑：告警捕获（仅打印前5条映射日志）
# ==============================================
log_info "=== Starting ${ALERT_RULE_NAME} alert check ==="
alert_rule_exists=false

# 步骤1：检查告警规则是否存在
set +e
log_debug "Checking if alert rule '${ALERT_RULE_NAME}' exists in Prometheus"
check_output=$(check_prom_alert_rule "$PROM_URL" "$ALERT_RULE_NAME" 2>&1)
ret=$?
log_debug "Alert rule check output: ${check_output}, return code: ${ret}"
set -e

if [ $ret -eq 0 ]; then
    alert_rule_exists=true
    log_info "Alert rule ${ALERT_RULE_NAME} exists in Prometheus"

    # 步骤2：获取当前节点的活跃告警（firing状态）
    set +e
    log_debug "Querying firing alerts for '${ALERT_RULE_NAME}' (Instance: ${INSTANCE})"
    # 1. 请求Prometheus告警API，筛选条件：告警名、当前实例、firing状态
    # 2. 提取labels.cpu（添加cpu前缀，如cpu58）和annotations.description（去括号）
    # 3. 输出格式：cpuXX|告警描述（便于后续分割）
    RAW_ALERT_DESC=$(curl -s --connect-timeout 5 "${PROM_URL}/api/v1/alerts" | \
        jq -r --arg r "$ALERT_RULE_NAME" --arg i "$INSTANCE" \
        '.data.alerts[] | select(
            .labels.alertname==$r and
            .labels.instance==$i and
            .state=="firing"
        ) | "cpu\(.labels.cpu)|\(.annotations.description)"' 2>/dev/null | \
        sed -E 's/\([^)]*\)//g')  # 移除告警描述中的括号及内容
    ret=$?

    # 统计活跃告警数量（处理空结果场景，避免wc -l误判为1）
    FIRING_COUNT=$(echo "$RAW_ALERT_DESC" | wc -l | awk '{print $1}')
    [ -z "$RAW_ALERT_DESC" ] && FIRING_COUNT=0
    log_debug "Firing alert data - count: ${FIRING_COUNT}, length: $(echo "$RAW_ALERT_DESC" | wc -c) bytes, return code: ${ret}"
    set -e

    # 步骤3：解析活跃告警并映射（仅打印前5条，优化序号显示）
    if [ $ret -eq 0 ] && [ "$FIRING_COUNT" -gt 0 ]; then
        log_warn "Found ${FIRING_COUNT} active ${ALERT_RULE_NAME} alert(s) (firing state)"
        # 预览前2条告警原始数据（避免刷屏）
        log_info "Alert details (first 2 lines preview):"
        echo "$RAW_ALERT_DESC" | head -n 2 | while read -r line; do
            log_info "  ${line}"
        done

        # 关键控制变量：序号从1开始计数（优化显示）
        map_count=1          # 已打印的映射日志计数（从1开始）
        MAX_PREVIEW=5        # 最大预览条数（可按需调整）
        total_map=0          # 总映射数（用于最终统计提示）

        # 遍历解析并映射告警
        while IFS='|' read -r cpu_key desc; do
            # 仅处理有效数据（避免空键/空描述）
            if [ -n "$cpu_key" ] && [ -n "$desc" ]; then
                # 存入关联数组（后续频率解析时用）
                ALERT_INFO_MAP["$cpu_key"]="$desc"
                total_map=$((total_map + 1))  # 累计总映射数

                # 仅打印前MAX_PREVIEW条映射日志（描述截断80字符）
                if [ $map_count -le $MAX_PREVIEW ]; then
                    log_debug "Mapped alert ${map_count}: ${cpu_key} → ${desc:0:80}..."  # 直接显示序号
                    map_count=$((map_count + 1))
                fi
            fi
        done < <(echo "$RAW_ALERT_DESC")

        # 补充总映射数说明（明确是否省略日志）
        if [ $total_map -gt $MAX_PREVIEW ]; then
            log_debug "Total mapped alerts: ${total_map} (omitted $((total_map - MAX_PREVIEW)) logs, only first ${MAX_PREVIEW} shown)"
        else
            log_debug "Total mapped alerts: ${total_map} (all logs shown above)"
        fi
    else
        log_info "No active ${ALERT_RULE_NAME} alerts for current node"
    fi
else
    alert_rule_exists=false
    log_warn "Alert rule ${ALERT_RULE_NAME} does not exist (skip alert checking)"
fi
log_info "=== Finished ${ALERT_RULE_NAME} alert check ==="


# ==============================================
# 步骤3：查询CPU频率数据并解析
# ==============================================
log_info "Start querying CPU frequency metrics from Prometheus"

# PromQL查询语句：当前频率 / 最大频率（计算频率占比）
FREQ_QUERY="node_cpu_scaling_frequency_hertz / node_cpu_scaling_frequency_max_hertz{instance=\"$INSTANCE\"}"
log_debug "PromQL query statement: ${FREQ_QUERY} (timeout: 10s)"

# 执行查询（临时关闭set -e）
set +e
log_debug "Executing query against Prometheus: ${PROM_URL}"
PROM_RESP=$(query_prometheus "$PROM_URL" "$FREQ_QUERY" 10)
ret=$?
log_debug "Prometheus response - length: $(echo "$PROM_RESP" | wc -c) bytes, return code: ${ret}"
set -e

# 处理查询结果
if [ $ret -ne 0 ] || [ -z "$PROM_RESP" ]; then
    log_err "Prometheus query failed (empty response or request error)"
    # 调用util中定义的generate_yaml_entry生成错误条目
    YAML+=$(generate_yaml_entry "CPU_Freq_Query" "Unknown" "Empty response or query failed" "error")$'\n'
else
    # 检查jq工具（JSON解析必需）
    if ! command -v jq &>/dev/null; then
        log_err "jq tool not found (required for Prometheus JSON response parsing)"
        # 调用util中定义的generate_yaml_entry生成错误条目
        YAML+=$(generate_yaml_entry "CPU_Freq_Parsing" "Failed" "jq tool missing" "error")$'\n'
    else
        # 统计频率记录数量
        RESULT_COUNT=$(echo "$PROM_RESP" | jq -r '.data.result | length // 0')
        log_info "Found ${RESULT_COUNT} CPU frequency records in Prometheus"

        # 处理无数据场景
        if [ "$RESULT_COUNT" -eq 0 ]; then
            log_warn "No CPU frequency data available in Prometheus (last query window)"
            # 调用util中定义的generate_yaml_entry生成警告条目
            YAML+=$(generate_yaml_entry "CPU_Freq_Overall" "NoData" "No metrics in Prometheus" "warn")$'\n'
        else
            log_debug "Start parsing ${RESULT_COUNT} frequency records"
            parsed_count=0  # 解析成功计数
            PARSED_YAML=""  # 存储解析后的YAML条目

            # 遍历解析每条频率记录
            while read -r ITEM; do
                RAW_DATA=$(echo "$ITEM" | base64 -d)
                # 提取CPU标识（如"0"→"cpu0"）
                RAW_CPU=$(echo "$RAW_DATA" | jq -r '.metric.cpu // "unknown"')
                CPU_KEY="cpu${RAW_CPU}"
                # 提取频率比值并转为百分比（保留1位小数）
                FREQ_RATIO_RAW=$(echo "$RAW_DATA" | jq -r '.value[1] // "0"')
                FREQ_RATIO=$(echo "scale=1; ${FREQ_RATIO_RAW} * 100" | bc | xargs printf "%.1f")

                # 匹配告警信息（从ALERT_INFO_MAP中获取）
                level=""
                err=""
                if [ -n "${ALERT_INFO_MAP[$CPU_KEY]}" ]; then
                    level="warn"
                    err="${ALERT_INFO_MAP[$CPU_KEY]}"
                fi

                # 调用util中定义的generate_yaml_entry生成当前CPU的YAML条目
                PARSED_YAML+=$(generate_yaml_entry "$CPU_KEY" "${FREQ_RATIO}%" "$err" "$level")$'\n'
                parsed_count=$((parsed_count + 1))
            done < <(echo "$PROM_RESP" | jq -r '.data.result[] | @base64')

            # 合并解析结果到总YAML
            if [ -n "$PARSED_YAML" ]; then
                YAML+="$PARSED_YAML"
                log_debug "Successfully parsed ${parsed_count} CPU frequency records"
            else
                log_warn "No valid CPU frequency data parsed from Prometheus response"
                # 调用util中定义的generate_yaml_entry生成警告条目
                YAML+=$(generate_yaml_entry "CPU_Freq_Parsing" "Failed" "No valid data" "warn")$'\n'
            fi
        fi
    fi
fi


# ==============================================
# 最终结果输出
# ==============================================
log_info "CPU frequency detection process completed. Generating final output"

# 打印完整YAML结果
log_debug "=== Generated YAML Content Start ==="
log_debug "$YAML"
log_debug "=== Generated YAML Content End ==="

# 模板渲染
RESULT=$(echo "$YAML" | jinja2 cpu_detect.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result "$RESULT"
log_info "CPU frequency detection finished successfully (Node: ${NodeName})"

#向eis的后端服务发送post请求，上报检测结果
set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret
