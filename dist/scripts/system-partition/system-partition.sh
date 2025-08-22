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
cd $(dirname "${BASH_SOURCE[0]}")
log_info "=================== system partition usage detection is running =========================="

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
    nsenter -t 1 -m -u -i -n mountpoint -q "$1"
}

# 通用检测函数
detect_partition_usage() {
	local name="$1" # 输出名字，如 root_usage_results
	local path="$2" # 挂载点路径
	local warn="$3" # 警告阈值
	local critical="$4" # 严重阈值

    YAML+=$(generate_yaml_detection "$name")$'\n'
	
    local total_size="none" usage="none" err="" level=""

	if check_is_mountpoint "$path"; then
		read total_size usage < <(get_partition_usage "$path")
		if [ "$usage" -ge "$critical" ]; then
			err="CRITICAL: Partition '${path}' is nearly full! Usage is ${usage}% of ${total_size}."
            level="warn"
		elif [ "$usage" -ge "$warn" ]; then
			err="WARNING: Partition '${path}' usage is high. Current usage: ${usage}% of ${total_size}."
            level="warn"
		fi


        YAML+=$(generate_yaml_entry "Total" "${total_size}" "$err" "$level")$'\n'
        YAML+=$(generate_yaml_entry "Used" "${usage}%" "$err" "$level")$'\n'
        
	else
        level="error"
        YAML+=$(generate_yaml_entry "Total" "none" "UNKNOWN: ${path} is not a mount point" "$level")$'\n'
        YAML+=$(generate_yaml_entry "Used" "none" "UNKNOWN: ${path} is not a mount point" "$level")$'\n'
	fi
}

## ===================开始检测=================
YAML=$(cat <<EOF
nodename: "$NodeName"
timestamp: "$Timestamp"
EOF
)$'\n'
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

# 生成yaml
for t in "${TARGETS[@]}"; do
    if [ -n "${PARTITIONS[$t]}" ]; then
        read path warn critical <<<"${PARTITIONS[$t]}"
        detect_partition_usage "_${t}_usage" $path $warn $critical
    else
        log_warn "WARN: Partition key '$t' not defined."
    fi
done


log_info "\n\n$YAML"
# 生成json
echo "$YAML" | jinja2 system-partition.j2 -o partition_usage.json --format=yaml

log_info "=================== system partition usage detection is completed =========================="
