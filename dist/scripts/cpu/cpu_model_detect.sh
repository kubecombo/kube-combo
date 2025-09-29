#!/bin/bash
set -e
set -o pipefail
#set -x  # 开启执行追踪

# 引入工具脚本
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/cpu.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"



# 初始化目录与环境变量
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

# 启动日志
log_info "Start CPU model detection"

# 初始化YAML结果集
YAML=$(generate_yaml_detection "cpu_model_results")$'\n'

# 核心检测逻辑：读取CPU型号信息
log_debug "Reading CPU model from /proc/cpuinfo"

# 读取vendor_id
set +e
log_debug "Start getting CPU vendor_id"
vendor_id=$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')
vendor_ret=$?
log_debug "Got vendor_id raw value: $vendor_id"
set -e

# 读取cpu_model
set +e
log_debug "Start getting CPU model name"
cpu_model=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}')
model_ret=$?
log_debug "Got model name raw value: $cpu_model"
set -e

# 处理vendor_id
if [ $vendor_ret -ne 0 ] || [ -z "$vendor_id" ]; then
    log_err "Failed to get CPU vendor information"
    YAML+=$(generate_yaml_entry "CPU_Vendor" "Unknown" "Failed to retrieve vendor_id from /proc/cpuinfo" "error")$'\n'
else
    log_info "Successfully got CPU vendor: $vendor_id"
    YAML+=$(generate_yaml_entry "CPU_Vendor" "$vendor_id" "" "")$'\n'
fi

# 处理cpu_model
if [ $model_ret -ne 0 ] || [ -z "$cpu_model" ]; then
    log_err "Failed to get CPU model information"
    YAML+=$(generate_yaml_entry "CPU_Model" "Unknown" "Failed to retrieve model name from /proc/cpuinfo" "error")$'\n'
else
    log_info "Successfully got CPU model: $cpu_model"
    YAML+=$(generate_yaml_entry "CPU_Model" "$cpu_model" "" "")$'\n'
fi

# 增加YAML调试
log_debug "Current YAML content: $YAML"

# 输出YAML
log_info "=== Start of YAML variable content ==="
log_info "$YAML"
log_info "=== End of YAML variable content  ==="

# 模板渲染
log_info "Preparing to render the template..."
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