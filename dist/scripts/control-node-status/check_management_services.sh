#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start management services detection"
YAML=$(generate_yaml_detection "management_services_results")$'\n'

tmp_yaml=$(mktemp)

# 获取当前节点名称和ID
current_node=$(echo "$(hostname -s)" | tr '[:upper:]' '[:lower:]')
node_id=$(echo "$current_node" | grep -o -E '0[0-9]{1}' | tail -1)

# 定义服务检测配置
declare -A services=(
    ["Kubelet"]="systemctl:kubelet:all:active"
    ["Containerd"]="systemctl:containerd:all:active"
    ["Chronyd"]="systemctl:chronyd:all:active"
    ["Keepalived"]="custom:/apps/sh/keepalived.sh status:01,02,03:is running"
    ["Haproxy"]="custom:/apps/sh/haproxy.sh status:01,02,03:is running"
    ["Mysql"]="systemctl:mysql:01,02:active"
    ["Harbor"]="systemctl:harbor:02,03:active"
    ["Registry"]="nerdctl:sealer-registry:01:Up"
)

# 检查每个服务
for service in "${!services[@]}"; do
    IFS=':' read -r type name nodes expected <<< "${services[$service]}"

    # 检查节点范围
    if [ "$nodes" != "all" ] && [[ ! ",$nodes," =~ ",$node_id," ]]; then
        log_debug "服务 $service 不在当前节点ID $node_id 的检测范围内，跳过"
        continue
    fi

    value=""
    err=""
    level=""

    case $type in
        systemctl)
            if systemctl is-active --quiet "$name"; then
                value="Normal"
                err="$service status is Running"
                level=""
                log_info "$service 状态正常"
            else
                value="Abnormal"
                err="$service status is not Running (当前状态: $(systemctl is-active "$name"))"
                level="warn"
                log_warn "$service 状态异常: $err"
            fi
            ;;
        custom)
            output=$($name 2>/dev/null || echo "command failed")
            if [[ "$output" == *"$expected"* ]]; then
                value="Normal"
                err="$service status is normal"
                level=""
                log_info "$service 状态正常"
            else
                value="Abnormal"
                err="$service status is not normal (输出: $output)"
                level="warn"
                log_warn "$service 状态异常: $err"
            fi
            ;;
        nerdctl)
            status=$(nerdctl ps -a --format '{{.Names}} {{.Status}}' | grep "^$name " | awk '{print $2}' 2>/dev/null || echo "Unknown")
            if [ "$status" = "$expected" ]; then
                value="Normal"
                err="$service status is $expected"
                level=""
                log_info "$service 状态正常"
            else
                value="Abnormal"
                err="$service status is not $expected (当前状态: $status)"
                level="warn"
                log_warn "$service 状态异常: $err"
            fi
            ;;
    esac

    echo "  - key: \"$service\"" >> "$tmp_yaml"
    echo "    value: \"$value\"" >> "$tmp_yaml"
    echo "    err: \"$err\"" >> "$tmp_yaml"
    echo "    level: \"$level\"" >> "$tmp_yaml"
done

# 检查kube-system命名空间中的异常pod
abnormal_pods_info=$(kubectl get pods -n kube-system --no-headers -o wide 2>/dev/null | awk '$3 != "Running" && $3 != "Succeeded" {print $1, $3}' || echo "command failed")

if [ -z "$abnormal_pods_info" ] || [ "$abnormal_pods_info" = "command failed" ]; then
    value="Normal"
    err="All pods in kube-system namespace are Running"
    level=""
else
    value="Abnormal"
    err="Pods in kube-system namespace with abnormal status: $abnormal_pods_info"
    level="warn"
    log_warn "kube-system命名空间存在异常pod: $abnormal_pods_info"
fi

echo "  - key: \"kube-system Pods\"" >> "$tmp_yaml"
echo "    value: \"$value\"" >> "$tmp_yaml"
echo "    err: \"$err\"" >> "$tmp_yaml"
echo "    level: \"$level\"" >> "$tmp_yaml"

YAML+=$(cat "$tmp_yaml")
rm -f "$tmp_yaml"

log_debug "$YAML"
RESULT=$(echo "$YAML" | jinja2 check_control.j2 -D NodeName="$Hostname" -D Timestamp="$Timestamp")
log_result "$RESULT"
set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret