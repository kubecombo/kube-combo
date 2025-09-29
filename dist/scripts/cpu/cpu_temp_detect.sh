#!/bin/bash
set -e
set -o pipefail
# set -x  # 开启执行追踪

# 引入工具脚本
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/cpu.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"



##############################################################################
# 1. 环境变量初始化（统一缩进+变量用途注释）
##############################################################################
log_debug "[Env Init] Start initializing environment variables"

# 工作目录定位（脚本所在目录）
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || { log_err "[Env Init] Failed to switch working directory: ${dir}"; exit 1; }

# 核心变量定义（默认值兜底，确保环境兼容性）
PROM_NAMESPACE="monitoring"                  # Prometheus所在K8s命名空间
PROM_SERVICE="cmss-ekiplus-prometheus-system"  # Prometheus的K8s Service名称
PROM_PORT="9090"                             # Prometheus默认端口
ALERT_RULE_NAME="IPMICPUTemperatureCritical"  # 目标CPU温度告警规则名
declare -A ALERT_INFO_MAP                    # 存储告警映射：SensorName -> 告警描述

# 初始化结果日志
log_debug "[Env Init] Environment variables initialized successfully:"
log_debug "[Env Init]   - Node Name (NodeName): ${NodeName}"
log_debug "[Env Init]   - Working Directory (DIR): ${DIR}"
log_debug "[Env Init]   - Prometheus Namespace (PROM_NAMESPACE): ${PROM_NAMESPACE}"
log_debug "[Env Init]   - Prometheus Service (PROM_SERVICE): ${PROM_SERVICE}"


##############################################################################
# 2. 启动日志与YAML结果集初始化
##############################################################################
log_info "[Main Process] Start CPU temperature detection (Node: ${NodeName}, Time: ${Timestamp})"

# 初始化YAML结果容器
log_debug "[YAML Init] Start initializing YAML result set"
YAML=$(generate_yaml_detection "cpu_temp_results")$'\n'
log_debug "[YAML Init] Initial YAML content: [${YAML}]"


##############################################################################
# 3. 获取K8s节点Instance标识
##############################################################################
log_info "[Instance Fetch] Start retrieving K8s node Instance ID"

# 调用工具函数获取Instance
log_debug "[Instance Fetch] Call utility function: get_k8s_instance(${NodeName})"
INSTANCE=$(get_k8s_instance "$NodeName")
log_debug "[Instance Fetch] Raw value from utility function: [${INSTANCE}]"

# 校验Instance有效性
if [ -z "$INSTANCE" ]; then
    log_err "[Instance Fetch] Failed to get K8s node Instance ID"
    YAML+=$(generate_yaml_entry "CPU_Temp_Overall" "Unknown" "Failed to get Instance ID" "error")$'\n'
    exit 0
fi
log_info "[Instance Fetch] Current node Instance ID: ${INSTANCE}"


##############################################################################
# 4. 构建Prometheus访问地址并验证可达性
##############################################################################
log_info "[Prometheus Conn] Start building Prometheus access URL"

# 集群内Service访问格式：服务名.命名空间.svc.cluster.local:端口
PROM_URL="http://${PROM_SERVICE}.${PROM_NAMESPACE}.svc.cluster.local:${PROM_PORT}"
log_debug "[Prometheus Conn] Built Prometheus Service URL: ${PROM_URL}"

# 验证Prometheus服务可达性（超时5秒，避免阻塞）
log_debug "[Prometheus Conn] Verify service reachability: ${PROM_URL}/-/healthy"
if ! curl -s --connect-timeout 5 "${PROM_URL}/-/healthy" >/dev/null; then
    log_err "[Prometheus Conn] Prometheus Service is unreachable: ${PROM_URL}"
    YAML+=$(generate_yaml_entry "CPU_Temp_Overall" "Unknown" "Prometheus Service unreachable" "error")$'\n'
    exit 0
fi
log_info "[Prometheus Conn] Prometheus Service is reachable: ${PROM_URL}"


##############################################################################
# 5. 检查Prometheus告警规则并获取活跃告警
##############################################################################
log_info "[Alert Handler] Start processing Prometheus alert rule: ${ALERT_RULE_NAME}"

# 步骤1：检查告警规则是否存在
log_debug "[Alert Handler] Call utility function: check_prom_alert_rule(${PROM_URL}, ${ALERT_RULE_NAME})"
if check_prom_alert_rule "$PROM_URL" "$ALERT_RULE_NAME"; then
    log_info "[Alert Handler] Alert rule exists: ${ALERT_RULE_NAME}"

    # 步骤2：查询当前节点的活跃告警
    log_debug "[Alert Handler] Query active alerts for current node: Instance=${INSTANCE}, State=firing"
    RAW_ALERT_DATA=$(curl -s "${PROM_URL}/api/v1/alerts" | \
        jq -r --arg alert "${ALERT_RULE_NAME}" --arg target "${INSTANCE}" \
        '.data.alerts[] | select(.labels.alertname == $alert and .labels.target == $target and .state == "firing") | "\(.labels.SensorName)::\(.annotations.description)"')
    log_debug "[Alert Handler] Raw active alert data: [${RAW_ALERT_DATA}]"

    # 步骤3：解析活跃告警并存储到映射表
    if [ -n "$RAW_ALERT_DATA" ]; then
        log_warn "[Alert Handler] Active alerts found (Count: $(echo "${RAW_ALERT_DATA}" | wc -l))"

        # 遍历每条告警数据
        while IFS= read -r line; do
            [ -z "$line" ] && continue  # 跳过空行
            log_debug "[Alert Handler] Parsing alert line: [${line}]"

            # 拆分SensorName与告警描述（按::分隔）
            IFS='::' read -r sensor pure_desc <<< "$line"
            sensor=$(echo "$sensor" | tr '[:lower:]' '[:upper:]')  # 统一SensorName为大写
            log_debug "[Alert Handler] Split result: SensorName=${sensor}, Raw Description=${pure_desc}"

            # 校验拆分有效性
            if [ -n "$sensor" ] && [ -n "$pure_desc" ]; then
                # 清理告警描述（去除括号内容、多余空格）
                cleaned_desc=$(echo "$pure_desc" | \
                    sed -E 's/\([^)]*\)//g' |  # 去除括号及内容
                    sed -E 's/  +/ /g' |       # 合并连续空格
                    sed -E 's/ $//')           # 去除末尾空格
                log_debug "[Alert Handler] Cleaned description: ${cleaned_desc}"

                # 存储到映射表
                ALERT_INFO_MAP["$sensor"]="$cleaned_desc"
                log_warn "[Alert Handler] Alert recorded: ${sensor} -> ${cleaned_desc}"
            else
                log_err "[Alert Handler] Failed to split SensorName and description, skip line: [${line}]"
            fi
        done < <(echo "$RAW_ALERT_DATA")
    else
        log_info "[Alert Handler] No active alerts found for current node: ${ALERT_RULE_NAME}"
    fi

    # 打印告警映射表
    log_debug "[Alert Handler] Alert mapping table summary:"
    for key in "${!ALERT_INFO_MAP[@]}"; do
        log_debug "[Alert Handler]   ${key} -> ${ALERT_INFO_MAP[$key]}"
    done
else
    log_warn "[Alert Handler] Alert rule does not exist: ${ALERT_RULE_NAME}"
fi


##############################################################################
# 6. 查询Prometheus温度指标并生成YAML结果
##############################################################################
log_info "[Temp Query] Start querying CPU temperature metrics from Prometheus"

# 温度查询语句
TEMP_QUERY="max by (SensorName) (last_over_time(
    ipmi_sensor_status{
        SensorID=\"processor\",
        SensorName=~\"(?i)^cpu(?:[ _-]*[0-9]+)?(?:[ _-]*(?:core(?:[ _-]*rem)?))?(?:[ _-]*(?:temp|temperature))?(?:[ _-]*[0-9]+)?$\",
        target=\"${INSTANCE}\",
        SensorStatus!=\"N/A\",
        SensorType=\"Temperature\"
    }[10m]
))"
log_debug "[Temp Query] PromQL query statement: ${TEMP_QUERY}"

# 调用工具函数查询温度数据（超时10秒）
log_debug "[Temp Query] Call utility function: query_prometheus(${PROM_URL}, [query], 10)"
PROM_RESP=$(query_prometheus "$PROM_URL" "$TEMP_QUERY" 10)
log_debug "[Temp Query] Raw response from Prometheus: [${PROM_RESP}]"

# 解析查询结果并生成YAML
log_info "[Result Gen] Start parsing temperature data and generating YAML"
if [ -z "$PROM_RESP" ]; then
    log_err "[Result Gen] Temperature query failed (empty response)"
    YAML+=$(generate_yaml_entry "CPU_Temp_Overall" "Unknown" "Temperature query failed (empty response)" "error")$'\n'
else
    # 调用工具函数解析结果
    log_debug "[Result Gen] Call utility function: parse_prom_result(${PROM_RESP})"
    PARSED_RESULT=$(parse_prom_result "$PROM_RESP")
    log_debug "[Result Gen] Parsed data: [${PARSED_RESULT}]"

    # 处理解析结果
    if [ "$PARSED_RESULT" = "NoData" ]; then
        log_warn "[Result Gen] No temperature data obtained (last 10 minutes)"
        YAML+=$(generate_yaml_entry "CPU_Temp_Overall" "NoData" "No temperature data (last 10 minutes)" "warn")$'\n'
    else
        log_info "[Result Gen] Processing parsed data (Total $(echo "${PARSED_RESULT}" | wc -l) records)"

        # 遍历每条温度记录
        while IFS='::' read -r metric value; do
            log_debug "[Result Gen] Processing record: metric=[${metric}], value=[${value}]"

            # 提取SensorName（统一为大写）
            SENSOR=$(echo "$metric" | grep -oP 'SensorName=\K[^,]+' 2>/dev/null || echo "Unknown_Sensor")
            SENSOR=$(echo "$SENSOR" | tr '[:lower:]' '[:upper:]')
            log_debug "[Result Gen] Extracted SensorName: ${SENSOR}"

            # 清理温度值（只保留数字和小数点）
            clean_value=$(echo "$value" | sed -E 's/[^0-9.]//g')
            [ -z "$clean_value" ] && clean_value="Unknown"
            log_debug "[Result Gen] Cleaned temperature value: ${clean_value}℃ (Raw: ${value})"

            # 匹配告警描述（从映射表中获取）
            err="${ALERT_INFO_MAP[$SENSOR]:-}"
            level="$([ -n "$err" ] && echo "warn" || echo "")"
            log_debug "[Result Gen] Alert match result: err=[${err}], level=[${level}]"

            # 生成YAML条目
            YAML+=$(generate_yaml_entry "$SENSOR" "${clean_value}℃" "$err" "$level")$'\n'
            log_info "[Result Gen] YAML entry added: ${SENSOR} -> ${clean_value}℃ (Alert: ${err:---})"
        done < <(echo "$PARSED_RESULT")
    fi
fi


##############################################################################
# 7. 输出结果
##############################################################################
log_info "[Main Process] CPU temperature detection nearly completed, output final YAML"

# 打印完整YAML内容
log_info "[Result Output] === YAML Content Start ==="
log_info "[Result Output] ${YAML}"
log_info "[Result Output] === YAML Content End ==="

# 模板渲染与结果提交
log_debug "[Result Submit] Render template with jinja2: cpu_detect.j2"
RESULT=$( echo "$YAML" | jinja2 cpu_detect.j2 --format=yaml -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result "$RESULT"

log_info "[Main Process] CPU temperature detection completed (Node: ${NodeName})"

#向eis的后端服务发送post请求，上报检测结果
set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret