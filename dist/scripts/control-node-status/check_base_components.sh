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

log_info "Start base components detection"
YAML=$(generate_yaml_detection "base_components_results")$'\n'

tmp_yaml=$(mktemp)

# Define namespace patterns to check
namespaces=(
    "monitoring"
    "cdi"
    "kubevirt"
    "rbd-.*"
    "eis.*"
    "cert-manager"
)

found_rbd_ns=""
for ns_pattern in "${namespaces[@]}"; do
    # Get matching namespaces
    matched_ns=$(kubectl get namespaces -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -E "^$ns_pattern$" || echo "")
    
    if [ -z "$matched_ns" ]; then
        # For rbd-* namespaces, at least one must exist
        if [[ "$ns_pattern" == "rbd-.*" ]]; then
            if [ -z "$found_rbd_ns" ]; then
                echo "  - key: \"$ns_pattern\"" >> "$tmp_yaml"
                echo "    value: \"Abnormal\"" >> "$tmp_yaml"
                echo "    err: \"No namespaces matching pattern $ns_pattern found\"" >> "$tmp_yaml"
                echo "    level: \"warn\"" >> "$tmp_yaml"
                log_warn "No namespaces matching pattern $ns_pattern found"
            fi
        else
            echo "  - key: \"$ns_pattern\"" >> "$tmp_yaml"
            echo "    value: \"Abnormal\"" >> "$tmp_yaml"
            echo "    err: \"No namespaces matching pattern $ns_pattern found\"" >> "$tmp_yaml"
            echo "    level: \"warn\"" >> "$tmp_yaml"
            log_warn "No namespaces matching pattern $ns_pattern found"
        fi
        continue
    fi

    # Mark rbd-* namespace as found
    if [[ "$ns_pattern" == "rbd-.*" ]]; then
        found_rbd_ns=1
    fi

    # Check pods in each matching namespace
    while IFS= read -r ns; do
        abnormal_pods_info=$(kubectl get pods -n "$ns" --no-headers -o wide 2>/dev/null | awk '$3 != "Running" && $3 != "Succeeded" {print $1, $3}' || echo "command failed")
        
        if [ -z "$abnormal_pods_info" ] || [ "$abnormal_pods_info" = "command failed" ]; then
            value="Normal"
            err="All pods in $ns namespace are Running"
            level=""
            log_info "All pods in $ns namespace are in normal state"
        else
            value="Abnormal"
            err="Pods in $ns namespace with abnormal status: $abnormal_pods_info"
            level="warn"
            log_warn "Abnormal pods found in $ns namespace: $abnormal_pods_info"
        fi
        
        echo "  - key: \"$ns\"" >> "$tmp_yaml"
        echo "    value: \"$value\"" >> "$tmp_yaml"
        echo "    err: \"$err\"" >> "$tmp_yaml"
        echo "    level: \"$level\"" >> "$tmp_yaml"
    done <<< "$matched_ns"
done

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