#!/bin/bash
set -e
set -o pipefail

# 引入工具脚本
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/cpu.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"




# ==============================================
# 初始化目录与环境变量
# ==============================================
log_debug "Start initializing directories and environment variables"

# 工作目录定位
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || { log_err "Failed to enter working directory: ${DIR}"; exit 1; }

# 核心变量定义
PROM_NAMESPACE="monitoring"                  # Prometheus所在命名空间
PROM_SERVICE="cmss-ekiplus-prometheus-system"  # Prometheus的Service名称
PROM_PORT="9090"                             # Prometheus默认端口

log_debug "Environment variables initialized:"
log_debug "  NodeName: ${NodeName}"
log_debug "  Timestamp: ${Timestamp}"
log_debug "  Working Dir: ${DIR}"
log_debug "  Prometheus Namespace: ${PROM_NAMESPACE}"


# ==============================================
# 启动日志与YAML初始化
# ==============================================
log_info "Start CPU load detection (compatible with all Bash versions)"
YAML=$(generate_yaml_detection "cpu_load_results")$'\n'
log_debug "Initialized YAML result set: ${YAML:0:50}..."  # 截断长内容


# ==============================================
# 步骤1：获取K8s Instance标识
# ==============================================
log_info "Start retrieving K8s Instance for node: ${NodeName}"

set +e
log_debug "Calling get_k8s_instance() with NodeName: ${NodeName}"
INSTANCE=$(get_k8s_instance "$NodeName" 2>&1)  # 捕获stderr避免漏错
ret=$?
log_debug "Raw Instance result: '$INSTANCE', return code: ${ret}"
set -e

# 校验Instance有效性
if [ $ret -ne 0 ] || [ -z "$INSTANCE" ] || [[ "$INSTANCE" =~ "error|failed" ]]; then
    log_err "Failed to get K8s Instance (ret: ${ret}, result: '$INSTANCE')"
    YAML+=$(generate_yaml_entry "CPU_Load_Instance" "Unknown" "Failed to get K8s Instance (kubectl issue)" "error")$'\n'
    log_debug "Exit with current YAML: ${YAML}"
    exit 0
fi
log_info "Successfully retrieved K8s Instance: ${INSTANCE}"


# ==============================================
# 步骤2：构建Prometheus Service URL并验证可达性
# ==============================================
log_info "Start building Prometheus Service URL"

# 集群内Service访问格式：http://服务名.命名空间.svc.cluster.local:端口
PROM_URL="http://${PROM_SERVICE}.${PROM_NAMESPACE}.svc.cluster.local:${PROM_PORT}"
log_debug "Built Prometheus Service URL: ${PROM_URL}"

# 验证Service可达性（超时5秒）
set +e
log_debug "Checking connectivity to ${PROM_URL}/-/healthy"
curl -s --connect-timeout 5 "${PROM_URL}/-/healthy" >/dev/null
ret=$?
set -e

if [ $ret -ne 0 ]; then
    log_err "Prometheus Service unreachable (URL: ${PROM_URL}, return code: ${ret})"
    YAML+=$(generate_yaml_entry "CPU_Load_Prometheus" "Unknown" "Prometheus Service unreachable" "error")$'\n'
    log_debug "Exit with current YAML: ${YAML}"
    exit 0
fi
log_info "Prometheus connection verified - Instance: ${INSTANCE}, URL: ${PROM_URL}"


# ==============================================
# 初始化关联数组（负载-告警映射）
# ==============================================
log_debug "Initializing load-alert and load-description mappings"

declare -A LOAD_ALERT=(
    ["node_load1"]="HighCPULoad1Min"
    ["node_load5"]="HighCPULoad5Min"
    ["node_load15"]="HighCPULoad15Min"
)
declare -A LOAD_DESC=(
    ["node_load1"]="node_load1"
    ["node_load5"]="node_load5"
    ["node_load15"]="node_load15"
)

log_debug "Load-Alert mapping initialized: ${!LOAD_ALERT[@]}"


# ==============================================
# 步骤3：批量检测负载指标
# ==============================================
log_info "Start batch detection for load metrics"

for metric in "node_load1" "node_load5" "node_load15"; do
    alert_rule=${LOAD_ALERT[$metric]:-UnknownAlert}
    yaml_key=${LOAD_DESC[$metric]:-$metric}
    alert_err=""
    rule_exists=false  # 显式定义规则存在标识

    log_info "Processing ${yaml_key} (metric: ${metric}, alert rule: ${alert_rule})"

    # ==============================================
    # 子步骤1：检查告警规则是否存在
    # ==============================================
    set +e
    log_debug "  Checking if alert rule '${alert_rule}' exists"
    rule_check_output=$(check_prom_alert_rule "$PROM_URL" "$alert_rule" 2>&1)
    rule_ret=$?

    # 判断规则是否存在
    if [ $rule_ret -eq 0 ] && [[ "$rule_check_output" != *"not found"* ]]; then
        rule_exists=true
        log_debug "  Alert rule '${alert_rule}' exists (output: ${rule_check_output})"

        # 获取活跃告警
        log_debug "  Querying firing alerts for '${alert_rule}' (Instance: ${INSTANCE})"
        raw_alert=$(get_prom_firing_alert "$PROM_URL" "$alert_rule" "$INSTANCE" 2>&1)
        alert_ret=$?
        log_debug "  Firing alert query result (ret: ${alert_ret}, length: $(echo "$raw_alert" | wc -c) bytes)"

        # 解析活跃告警
        if [ $alert_ret -eq 0 ] && [ -n "$raw_alert" ] && [[ "$raw_alert" != *"error"* ]]; then
            alert_err=$(echo "$raw_alert" | head -n 1 | \
                sed -E 's/\([^)]*\)//g' |
                sed -E 's/  +/ /g' |
                sed -E 's/ $//')
            log_warn "  Firing alert detected: ${alert_err}"
        else
            log_debug "  No firing alerts for '${alert_rule}' (ret: ${alert_ret})"
        fi
    else
        rule_exists=false
        log_warn "  Alert rule '${alert_rule}' not found (output: ${rule_check_output}, ret: ${rule_ret})"
    fi
    set -e


    # ==============================================
    # 子步骤2：查询负载指标
    # ==============================================
    set +e
    query="${metric}{instance=\"$INSTANCE\"}"
    log_debug "  Querying metric: ${query} (timeout: 5s)"
    PROM_RESP=$(query_prometheus "$PROM_URL" "$query" 5 2>&1)
    query_ret=$?
    log_debug "  Metric query result (ret: ${query_ret}, length: $(echo "$PROM_RESP" | wc -c) bytes)"
    set -e


    # ==============================================
    # 子步骤3：解析指标值
    # ==============================================
    set +e
    log_debug "  Parsing ${metric} from Prometheus response"
    LOAD_VALUE=$(parse_prom_result "$PROM_RESP" "$metric" 2>&1)
    parse_ret=$?

    # 标准化解析结果
    if [ "$LOAD_VALUE" = "NoData" ] || [[ "$LOAD_VALUE" =~ "no data" ]]; then
        LOAD_VALUE="NoData"
    elif [ $parse_ret -ne 0 ] || [[ "$LOAD_VALUE" =~ "error" ]]; then
        LOAD_VALUE="ParseFailed"
    fi
    log_debug "  Parsed ${metric} value: '${LOAD_VALUE}', return code: ${parse_ret}"
    set -e


    # ==============================================
    # 子步骤4：判断负载状态并生成YAML
    # ==============================================
    err=""
    level=""

    if [ $query_ret -ne 0 ] || [[ "$PROM_RESP" =~ "error|timeout" ]]; then
        err="Load query failed (timeout or invalid response)"
        level="error"
        log_err "  ${err} (ret: ${query_ret})"
    elif [ "$LOAD_VALUE" = "NoData" ]; then
        err="No ${yaml_key} data in Prometheus"
        level="warn"
        log_warn "  ${err}"
    elif [ "$LOAD_VALUE" = "ParseFailed" ]; then
        err="Failed to parse ${yaml_key} data"
        level="error"
        log_err "  ${err} (ret: ${parse_ret})"
    else
        if [ -n "$alert_err" ]; then
            err="$alert_err"
            level="warn"
            log_warn "  ${err}: ${yaml_key} = ${LOAD_VALUE}"
        else
            log_info "  ${yaml_key} detected successfully: ${LOAD_VALUE}"
        fi
    fi

    # 生成YAML条目
    yaml_entry=$(generate_yaml_entry "$yaml_key" "$LOAD_VALUE" "$err" "$level")
    YAML+="$yaml_entry"$'\n'
    log_debug "  Generated YAML entry:\n${yaml_entry}"
done


# ==============================================
# 输出最终结果
# ==============================================
log_info "Load detection completed. Generating final output"
log_debug "=== Generated YAML Content Start ==="
log_debug "${YAML}"
log_debug "=== Generated YAML Content End ==="

# 模板渲染与结果提交
RESULT=$( echo "$YAML" | jinja2 cpu_detect.j2 --format=yaml -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result "$RESULT"
log_info "CPU load detection process finished successfully"

#向eis的后端服务发送post请求，上报检测结果
set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret
