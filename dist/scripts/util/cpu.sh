# ==============================================
# CPU 检测通用工具函数
# ==============================================
# 1. 获取 K8s 节点 Instance 名称
# 参数：$1 - 节点主机名
# 返回：Instance 名称；失败返回空字符串
get_k8s_instance() {
    local node_name="${1:-$(hostname)}"
    local instance=""
    set +e
    # 尝试通过 kubectl 获取节点的 metadata.name（K8s 环境下的 Instance 标识）
    instance=$(kubectl get node "$node_name" -o jsonpath='{.metadata.name}' 2>/dev/null)
    set -e
    if [ -z "$instance" ]; then
        log_debug "Failed to get K8s Instance: kubectl unavailable or not in K8s"
        return 1
    fi
    echo "$instance"
    return 0
}

# 2. 获取 Prometheus 服务 IP  用了service,所以这块ip没用到
# 参数：$1 - Prometheus 命名空间；$2 - Prometheus 服务名
# 返回：Prometheus 集群 IP；失败返回空字符串
get_prometheus_ip() {
    if [ $# -ne 2 ]; then
        log_err "Usage: get_prometheus_ip <namespace> <service_name>" >&2
        return 1
    fi

    local namespace="$1"
    local service_name="$2"
    local prom_ip=""

    set +e
    # 从 K8s 服务中获取集群 IP
    prom_ip=$(kubectl get svc -n "$namespace" "$service_name" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    set -e

    if [ -z "$prom_ip" ]; then
        log_debug "Failed to get Prometheus IP: service $namespace/$service_name not found"
        return 1
    fi

    echo "$prom_ip"
    return 0
}

# 3. 执行 Prometheus 指标查询
# 参数：$1 - Prometheus 完整 URL（如 http://service.namespace.svc:9090）；$2 - 查询语句；$3 - 超时时间（秒，可选，默认5）
# 返回：查询结果（JSON格式）；失败返回空字符串
query_prometheus() {
    if [ $# -lt 2 ]; then
        log_err "Usage: query_prometheus <prom_url> <query> [timeout]" >&2
        return 1
    fi

    local prom_url="$1"  # 现在接受完整URL（含协议、主机、端口）
    local query="$2"
    local timeout="${3:-5}"
    local full_url="${prom_url}/api/v1/query"  # 拼接查询接口路径
    local response=""

    set +e
    # 带超时的 curl 查询，禁止输出进度信息
    response=$(curl -s --connect-timeout "$timeout" --max-time "$timeout" \
        --data-urlencode "query=$query" "$full_url" 2>/dev/null)
    set -e

    # 验证响应状态是否为 success
    local status=$(echo "$response" | jq -r '.status' 2>/dev/null)
    if [ "$status" != "success" ]; then
        log_debug "Prometheus query failed: status=$status, query=$query, url=$full_url"
        return 1
    fi

    echo "$response"
    return 0
}

# 4. 检查 Prometheus 告警规则是否存在
# 参数：$1 - Prometheus 完整 URL；$2 - 告警规则名称
# 返回：存在返回 0，不存在返回 1
check_prom_alert_rule() {
    if [ $# -ne 2 ]; then
        log_err "Usage: check_prom_alert_rule <prom_url> <alert_rule_name>" >&2
        return 2
    fi

    local prom_url="$1"  # 完整URL
    local rule_name="$2"
    local full_url="${prom_url}/api/v1/rules"  # 拼接规则接口路径
    local rule_exists=0

    set +e
    # 查询规则并统计匹配数量
    rule_exists=$(curl -s --connect-timeout 5 "$full_url" | \
        jq -r --arg r "$rule_name" '.data.groups[].rules[] | select(.name==$r) | .name' | \
        grep -c "$rule_name" 2>/dev/null)
    set -e

    if [ "$rule_exists" -eq 0 ]; then
        log_debug "Prometheus alert rule not found: $rule_name, url=$full_url"
        return 1
    fi

    return 0
}

# 5. 获取 Prometheus 活跃告警信息
# 参数：$1 - Prometheus 完整 URL；$2 - 告警规则名称；$3 - Instance 名称
# 返回：告警描述；无告警返回空字符串
get_prom_firing_alert() {
    if [ $# -ne 3 ]; then
        log_err "Usage: get_prom_firing_alert <prom_url> <alert_rule_name> <instance>" >&2
        return 1
    fi

    local prom_url="$1"  # 完整URL
    local rule_name="$2"
    local instance="$3"
    local full_url="${prom_url}/api/v1/alerts"  # 拼接告警接口路径
    local alert_desc=""

    set +e
    # 筛选状态为 firing 的目标告警
    alert_desc=$(curl -s --connect-timeout 5 "$full_url" | \
        jq -r --arg r "$rule_name" --arg i "$instance" \
        '.data.alerts[] | select(.labels.alertname==$r and .labels.instance==$i and .state=="firing") | .annotations.description' 2>/dev/null)
    set -e

    echo "$alert_desc"
    return 0
}

# 6. 解析 Prometheus 查询结果中的指标值（温度/负载/频率脚本共用）
# 参数：$1 - Prometheus 查询响应（JSON）；$2 - 指标名称（可选，用于单结果场景）
# 返回：指标值（单结果返回值，多结果返回 key:value 格式）；无数据返回 NoData
parse_prom_result() {
    if [ $# -lt 1 ]; then
        log_err "Usage: parse_prom_result <prom_response> [metric_name]" >&2
        return 1
    fi

    local response="$1"
    local metric_name="$2"
    local result_count=$(echo "$response" | jq -r '.data.result | length' 2>/dev/null)

    if [ "$result_count" -eq 0 ]; then
        echo "NoData"
        return 0
    fi

    # 单结果场景
    if [ -n "$metric_name" ] && [ "$result_count" -eq 1 ]; then
        local value=$(echo "$response" | jq -r '.data.result[0].value[1]' 2>/dev/null)
        echo "${value:-NoData}"
        return 0
    fi

    # 多结果场景
    echo "$response" | jq -r '.data.result[] | "\(.metric | to_entries[] | .key + "=" + .value)::\(.value[1])"' 2>/dev/null
    return 0
}
