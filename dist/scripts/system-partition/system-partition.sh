#!/bin/bash
set -e

## #####################################################################
# 脚本名称  : systemPartitionDetection.sh
# 功能      :
#   1. 获取指定分区的使用情况
#   2. 支持命令行参数指定要检测的分区
#   3. 输出结果为 JSON 格式
#
# 支持的分区参数:
#   root           -> /
#   boot           -> /boot
#   boot_efi       -> /boot/efi
#   apps_data_etcd -> /apps/data/etcd
#   var            -> /var
#   apps           -> /apps
#   k8s_temp       -> /k8s_temp
#
# 使用示例:
#   bash systemPartitionDetection.sh
#       -> 检测所有支持的分区
#
#   bash systemPartitionDetection.sh root boot
#       -> 只检测 root 和 boot 分区
## #####################################################################

source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"
cd $(dirname "${BASH_SOURCE[0]}")
log_info "=================== system partition usage detection is running =========================="
log_debug "\n\n$(nsenter -t 1 -m -u -i -n df -h | grep -v shm | grep -v containerd | grep -v kubelet)\n\n"

# 获取分区总大小和使用率
get_partition_usage() {
	local path=$1
	local info=$(nsenter -t 1 -m -u -i -n df -Ph "$path" | awk 'END {gsub("%","",$5); print $2,$5}')
	local total_size=$(echo $info | awk '{print $1}')
	local usage=$(echo $info | awk '{print $2}')
	echo "$total_size $usage"
}

# 判断是否挂载
check_is_mountpoint() {
	# 将错误输出重定向到 stdout（方便后续捕获）
    nsenter -t 1 -m -u -i -n mountpoint -q "$1"
}

# 通用检测函数
detect_partition_usage() {
	local name="$1" # 输出名字，如 root_usage_results
	local path="$2" # 挂载点路径
	local high_pressure="$3" # 警告阈值
	local extreme_pressure="$4" # 严重阈值

    YAML+=$(generate_yaml_detection "$name")$'\n'
	
    local total_size="none" usage="none" err="" level=""

	if ! nsenter -t 1 -m -u -i -n test -d "$path" 2>/dev/null; then
		level="error"
        YAML+=$(generate_yaml_entry "Total" "none" "ERROR: '${path}' is not a directory." "$level")$'\n'
        YAML+=$(generate_yaml_entry "Used" "none" "ERROR: '${path}' is not a directory." "$level")$'\n'
	elif check_is_mountpoint "$path"; then
		read total_size usage < <(get_partition_usage "$path")
		if [ "$usage" -ge "$extreme_pressure" ]; then
			err="EXTREME PRESSURE: Partition '${path}' is nearly full! Usage is ${usage}% of ${total_size}."
			level="warn"
		elif [ "$usage" -ge "$high_pressure" ]; then
			err="HIGH PRESSURE: Partition '${path}' usage is high. Current usage: ${usage}% of ${total_size}."
			level="warn"
		else
			err=""
			level=""
		fi
        YAML+=$(generate_yaml_entry "Total" "${total_size}" "$err" "$level")$'\n'
        YAML+=$(generate_yaml_entry "Used" "${usage}%" "$err" "$level")$'\n'
        
	else
        level="error"
        YAML+=$(generate_yaml_entry "Total" "none" "ERROR: Partition '${path}' is not mounted." "$level")$'\n'
        YAML+=$(generate_yaml_entry "Used" "none" "ERROR: Partition '${path}' is not mounted." "$level")$'\n'
	fi
}

## ===================开始检测=================

YAML=""
# 定义：<待检测路径> <警告阈值> <严重阈值>
declare -A PARTITIONS=(
	["root"]="/ 80 90"
	["boot"]="/boot 80 90"
	["boot_efi"]="/boot/efi 80 90"
	["apps_data_etcd"]="/apps/data/etcd 80 90"
	["var"]="/var 80 90"
	["apps"]="/apps 80 90"
	["k8s_temp"]="/k8s_temp 80 90"
)

# 如果没有参数，默认检测 全部 分区
if [ $# -eq 0 ]; then
	TARGETS=("${!PARTITIONS[@]}")
else
	TARGETS=("$@")
fi

# 生成yaml, 不在列表中的，不会检测
for t in "${TARGETS[@]}"; do
    if [ -n "${PARTITIONS[$t]}" ]; then
        read path high_pressure extreme_pressure <<<"${PARTITIONS[$t]}"
        detect_partition_usage "_${t}_usage" $path $high_pressure $extreme_pressure
    else
        log_warn "WARN: Partition key 'data' is not defined, skip detection."
    fi
done


log_debug "\n\n$YAML"
# # 生成json
RESULT=$( echo "$YAML" | jinja2 system-partition.j2 -D nodeName="$NodeName" -D timestamp="$Timestamp")

log_result "$RESULT"


set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret