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

log_info "Start node status detection"
YAML=$(generate_yaml_detection "node_status_results")$'\n'

tmp_yaml=$(mktemp)

# Get hostname and node list
hostname=$(hostname -s)
current_node_name_lower=$(echo "$hostname" | tr '[:upper:]' '[:lower:]')

# Get control node list
control_nodes_list_all=($(kubectl get nodes -o jsonpath='{range .items[?(.metadata.labels.node-role\.kubernetes\.io/master)]}{.metadata.name}{"\n"}{end}' 2>/dev/null))
if [ ${#control_nodes_list_all[@]} -eq 0 ]; then
    control_nodes_list_all=($(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null))
    log_warn "No nodes with master label found, will check all nodes"
fi

# Find matching node name
found_node=""
for node in "${control_nodes_list_all[@]}"; do
    if [ "$(echo "$node" | tr '[:upper:]' '[:lower:]')" == "$current_node_name_lower" ]; then
        found_node="$node"
        break
    fi
done

if [ -z "$found_node" ]; then
    log_err "No node matching current hostname '$hostname' found in the cluster"
    echo "  - key: \"$hostname\"" >> "$tmp_yaml"
    echo "    value: \"Abnormal\"" >> "$tmp_yaml"
    echo "    err: \"Host name does not match any cluster node name\"" >> "$tmp_yaml"
    echo "    level: \"error\"" >> "$tmp_yaml"
else
    # Get node status
    status=$(kubectl get node "$found_node" -o jsonpath='{.status.conditions[?(.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    
    if [ "$status" = "True" ]; then
        value="Normal"
        err="Node $found_node status is normal"
        level=""
        log_info "Node $found_node status is normal"
    else
        value="Abnormal"
        err="Node $found_node status is not Ready (current: $status)"
        level="warn"
        log_warn "Node $found_node status is abnormal: $err"
    fi
    
    echo "  - key: \"$found_node\"" >> "$tmp_yaml"
    echo "    value: \"$value\"" >> "$tmp_yaml"
    echo "    err: \"$err\"" >> "$tmp_yaml"
    echo "    level: \"$level\"" >> "$tmp_yaml"
fi

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