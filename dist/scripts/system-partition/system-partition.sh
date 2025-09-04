#!/bin/bash
set -e

###########################################################
# 脚本功能：
# 1. 获取指定分区使用情况
# 2. 支持命令行参数指定要检测的分区
# 3. 输出 JSON

# 脚本命令行参数:
# root  /
# boot  /boot
# boot_efi  /boot/efi
# apps_data_etcd  /apps/data/etcd
# var  /var
# apps  /apps
# k8s_temp  /k8s_temp

# 使用示例:
# bash systemPartitionDetection.sh  检测所有项目
# bash systemPartitionDetection.sh root boot   只检测root和boot

#####################函数定义#########################

# 获取分区总大小和使用率
get_partition_usage() {
	local path=$1
	local info=$(df -Ph "$path" | awk 'END {gsub("%","",$5); print $2,$5}')
	local total_size=$(echo $info | awk '{print $1}')
	local usage=$(echo $info | awk '{print $2}')
	echo "$total_size $usage"
}

# 判断是否挂载
check_is_mountpoint() {
	mountpoint -q "$1"
}

# 通用检测函数
detect_partition_usage() {
	local name="$1" # 输出名字，如 root_usage_results
	local path="$2" # 挂载点路径
	local warn="$3" # 警告阈值
	local critical="$4" # 严重阈值

	local total_size="none" usage="none" err=""

	if check_is_mountpoint "$path"; then
		read total_size usage < <(get_partition_usage "$path")
		if [ "$usage" -ge "$critical" ]; then
			err="CRITICAL: partition ${path} usage is ${usage}%."
		elif [ "$usage" -ge "$warn" ]; then
			err="WARNING: partition ${path} usage is ${usage}%."
		fi

		cat << EOF
${name}:
  - key: "Total"
    value: "${total_size}"
    err: ""
  - key: "Used"
    value: "${usage}%"
    err: "${err}"
EOF
	else
		cat <<- EOF
			${name}:
			  - key: "Total"
			    value: "${total_size}"
			    err: "UNKNOWN: ${path} is not a mount point"
			  - key: "Used"
			    value: "${usage}"
			    err: "UNKNOWN: ${path} is not a mount point"
		EOF
	fi
}

## ===================开始检测=================

# 定义：<待检测路径> <警告阈值><严重阈值>
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
yaml_sections=""
for t in "${TARGETS[@]}"; do
	if [ -n "${PARTITIONS[$t]}" ]; then
		read path warn critical <<< "${PARTITIONS[$t]}"
		yaml_sections+=$(detect_partition_usage "_${t}_usage" $path $warn $critical)
		yaml_sections+=$'\n'
	else
		echo "WARN: Partition key '$t' not defined." >&2
	fi
done

yaml_data=$(
	cat << EOF
nodename: $(hostname)
timestamp: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
$yaml_sections
EOF
)

echo "$yaml_data" >&2
# 生成json
echo "$yaml_data" | jinja2 system-partition.j2 -o partition_usage.json --format=yaml
