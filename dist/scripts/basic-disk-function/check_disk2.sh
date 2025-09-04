#!/bin/bash

# 引入日志函数
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../log.sh"

# 获取当前时间戳（用于日志文件名，格式：202508041413）
log_timestamp=$(date +%Y%m%d%H%M)
# 脚本名称（不含路径和后缀）
script_name=$(basename "$0" .sh)

# 日志路径和文件名配置
LOG_DIR="/var/log/oneClickDetection/"
LOG_FILE="${LOG_DIR}${log_timestamp}-${script_name}.log"
# 输出文件路径（当前路径）
OUTPUT_YAML="./${script_name}.yaml"
OUTPUT_JSON="./${script_name}.json"
# 同级目录的Jinja模板文件路径
JINJA_TEMPLATE_FILE="./check_disk.j2"

# 检查并创建日志目录
if [ ! -d "$LOG_DIR" ]; then
	if ! mkdir -p "$LOG_DIR"; then
		echo "错误：无法创建日志目录 $LOG_DIR，请检查权限" >&2
		exit 1
	fi
	echo "日志目录不存在，已自动创建：$LOG_DIR"
fi

# 日志配置
# shellcheck disable=SC2034
LOG_LEVEL=2
# shellcheck disable=SC2034
LOG_FLAG=true

# 获取主机名和时间戳（YAML格式要求：yyyy:MM:dd HH:mm:ss）
hostname=$(hostname)
timestamp=$(date +"%Y:%m:%d %H:%M:%S")

log_info "====== 开始磁盘检查任务 ======"
log_debug "当前主机: $hostname"
log_debug "开始时间: $timestamp"
log_debug "日志文件路径: $LOG_FILE"
log_debug "输出YAML文件路径: $OUTPUT_YAML"
log_debug "输出JSON文件路径: $OUTPUT_JSON"
log_debug "Jinja模板文件路径: $JINJA_TEMPLATE_FILE"

# 初始化YAML文件
> "$OUTPUT_YAML"
echo "nodename: \"$hostname\"" >> "$OUTPUT_YAML"
echo "timestamp: \"$timestamp\"" >> "$OUTPUT_YAML"
echo "" >> "$OUTPUT_YAML"

# 检查依赖工具是否存在
check_dependency() {
	local cmd=$1
	if ! command -v "$cmd" &> /dev/null; then
		log_err "依赖工具 $cmd 未安装，请先安装"
		exit 1
	fi
}

# 检查必要依赖
check_dependency "lsblk"
check_dependency "iostat"
check_dependency "smartctl"
check_dependency "fio"

# 过滤非物理磁盘（排除虚拟/网络设备）
is_physical_disk() {
	local disk=$1
	if echo "$disk" | grep -qE "^nbd|^rbd|^loop|^dm-"; then
		return 1
	fi
	if [ -d "/sys/block/$disk/device" ]; then
		return 0
	fi
	return 1
}

# ========== 实际检测函数（输出YAML格式片段） ==========

# 1. 检测物理磁盘在线状态
check_disk_status() {
	log_info "开始检测物理磁盘在线状态..."
	log_debug "执行命令: lsblk -d -o NAME,MODEL"

	echo "disk_status_results:" >> "$OUTPUT_YAML"

	while IFS= read -r disk; do
		local disk_name=$(echo "$disk" | awk '{print $1}')
		if ! is_physical_disk "$disk_name"; then
			log_debug "跳过非物理磁盘: $disk_name"
			continue
		fi
		if [ -d "/sys/block/$disk_name/device" ]; then
			local status="online"
			local model=$(echo "$disk" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
			echo "  - key: \"$disk_name\"" >> "$OUTPUT_YAML"
			echo "    value: \"$model\"" >> "$OUTPUT_YAML"
			echo "    err: \"$status\"" >> "$OUTPUT_YAML"
		fi
	done < <(lsblk -d -o NAME,MODEL | grep -v "^NAME")

	echo "" >> "$OUTPUT_YAML"
	log_info "物理磁盘在线状态检测完成"
}

# 2. 检测磁盘IO繁忙度
check_disk_busy() {
	log_info "开始检测磁盘IO繁忙度..."
	log_debug "执行命令: iostat -x 1 1"

	echo "disk_busy_results:" >> "$OUTPUT_YAML"

	while IFS= read -r line; do
		local disk=$(echo "$line" | awk '{print $1}')
		if ! is_physical_disk "$disk"; then
			log_debug "跳过非物理磁盘的繁忙度检测: $disk"
			continue
		fi
		local util=$(echo "$line" | awk '{print $14}')
		if (($(echo "$util < 70" | bc -l))); then
			local level="正常"
			local err_msg=""
		elif (($(echo "$util < 80" | bc -l))); then
			local level="高"
			local err_msg=""
		elif (($(echo "$util < 90" | bc -l))); then
			local level="较高"
			local err_msg="磁盘 $disk 繁忙度较高: $util%"
			log_warn "$err_msg"
		else
			local level="非常高"
			local err_msg="磁盘 $disk 繁忙度非常高: $util%"
			log_err "$err_msg"
		fi
		echo "  - key: \"$disk (%)\"" >> "$OUTPUT_YAML"
		echo "    value: \"$util\"" >> "$OUTPUT_YAML"
		echo "    err: \"$level\"" >> "$OUTPUT_YAML"
	done < <(iostat -x 1 1 | grep -vE "^avg-cpu|^Device|^$")

	echo "" >> "$OUTPUT_YAML"
	log_info "磁盘IO繁忙度检测完成"
}

# 3. 检测SSD剩余寿命（仅物理SSD）
check_ssd_lifetime() {
	log_info "开始检测SSD剩余寿命..."
	log_debug "执行命令: smartctl -a <disk>"

	echo "ssd_lifetime_results:" >> "$OUTPUT_YAML"

	while IFS= read -r disk; do
		local disk_name=$(echo "$disk" | awk '{print $1}')
		if ! is_physical_disk "$disk_name" || [ "$(cat /sys/block/"$disk_name"/queue/rotational 2> /dev/null)" -ne 0 ]; then
			log_debug "跳过非物理SSD: $disk_name"
			continue
		fi
		local remaining="未知"
		local status="无法获取寿命信息"
		local lifetime_output=$(sudo smartctl -a "/dev/$disk_name" 2> /dev/null)

		if echo "$lifetime_output" | grep -q "Percentage Used"; then
			remaining=$(echo "$lifetime_output" | grep "Percentage Used" | awk '{print 100 - $3}')
			status="正常"
		elif echo "$lifetime_output" | grep -q "Remaining Life"; then
			remaining=$(echo "$lifetime_output" | grep "Remaining Life" | awk '{print $4}' | sed 's/%//')
			status="正常"
		fi

		if [ "$remaining" -lt 20 ] && [ "$remaining" != "未知" ]; then
			status="寿命不足，建议更换"
			log_err "SSD $disk_name 剩余寿命低: $remaining%"
		fi

		echo "  - key: \"$disk_name\"" >> "$OUTPUT_YAML"
		echo "    value: \"$remaining%\"" >> "$OUTPUT_YAML"
		echo "    err: \"$status\"" >> "$OUTPUT_YAML"
	done < <(lsblk -d -o NAME,MODEL | grep -v "^NAME")

	echo "" >> "$OUTPUT_YAML"
	log_info "SSD剩余寿命检测完成"
}

# 4. 检测SSD接口模式（仅物理SSD）
check_ssd_interface_mode() {
	log_info "开始检测SSD接口模式..."
	log_debug "执行命令: smartctl -i <disk>"

	echo "ssd_interface_mode_results:" >> "$OUTPUT_YAML"

	while IFS= read -r disk; do
		local disk_name=$(echo "$disk" | awk '{print $1}')
		if ! is_physical_disk "$disk_name" || [ "$(cat /sys/block/"$disk_name"/queue/rotational 2> /dev/null)" -ne 0 ]; then
			log_debug "跳过非物理SSD的接口检测: $disk_name"
			continue
		fi

		local mode="未知"
		local status="无法识别接口（可能不支持SMART）"
		local interface_info=$(sudo smartctl -i "/dev/$disk_name" 2> /dev/null)

		if echo "$interface_info" | grep -q "SATA Version"; then
			mode=$(echo "$interface_info" | grep "SATA Version" | awk -F: '{print $2}' | sed 's/^[ \t]*//')
			if echo "$mode" | grep -qE "3.0|6.0 Gbps"; then
				status="正常"
			else
				status="异常（建议SATA3模式）"
				log_warn "SSD $disk_name 接口模式不达标: $mode"
			fi
		elif echo "$interface_info" | grep -q "NVMe"; then
			mode="NVMe"
			status="正常"
		fi

		echo "  - key: \"$disk_name\"" >> "$OUTPUT_YAML"
		echo "    value: \"$mode\"" >> "$OUTPUT_YAML"
		echo "    err: \"$status\"" >> "$OUTPUT_YAML"
	done < <(lsblk -d -o NAME,MODEL | grep -v "^NAME")

	echo "" >> "$OUTPUT_YAML"
	log_info "SSD接口模式检测完成"
}

# 5. 磁盘性能检测
check_disk_performance() {
	log_info "开始磁盘性能检测（fio测试）..."
	log_debug "执行命令: sudo fio [参数]"

	local test_dir="/tmp/disk-test"
	mkdir -p "$test_dir" || {
		log_err "无法创建测试目录 $test_dir"
		echo "disk_performance_results:" >> "$OUTPUT_YAML"
		echo "  - key: \"fio测试\"" >> "$OUTPUT_YAML"
		echo "    value: \"失败\"" >> "$OUTPUT_YAML"
		echo "    err: \"测试目录创建失败\"" >> "$OUTPUT_YAML"
		echo "" >> "$OUTPUT_YAML"
		return 1
	}

	local fio_cmd="sudo fio --name=disk_perf_test --rw=randrw --direct=1 --bs=4k --numjobs=4 --iodepth=32 --size=100M --runtime=10 --group_reporting --directory=$test_dir"
	log_debug "执行fio命令: $fio_cmd"

	local fio_output=$(eval $fio_cmd 2>&1)
	local fio_exit_code=$?
	rm -rf "$test_dir"

	echo "disk_performance_results:" >> "$OUTPUT_YAML"
	if [ $fio_exit_code -ne 0 ]; then
		log_err "fio测试执行失败，错误信息: $fio_output"
		echo "  - key: \"fio测试\"" >> "$OUTPUT_YAML"
		echo "    value: \"失败\"" >> "$OUTPUT_YAML"
		echo "    err: \"fio执行失败\"" >> "$OUTPUT_YAML"
	else
		local read_iops=$(echo "$fio_output" | grep -i "read:.*iops" | awk -F'[=,]' '{print $2}' | sed 's/ //g')
		local write_iops=$(echo "$fio_output" | grep -i "write:.*iops" | awk -F'[=,]' '{print $2}' | sed 's/ //g')
		local read_bw=$(echo "$fio_output" | grep -i "read:.*bw" | awk -F'BW=' '{print $2}' | awk '{print $1}')
		local write_bw=$(echo "$fio_output" | grep -i "write:.*bw" | awk -F'BW=' '{print $2}' | awk '{print $1}')

		log_debug "磁盘性能测试结果: 读IOPS=$read_iops, 写IOPS=$write_iops, 读带宽=$read_bw, 写带宽=$write_bw"
		echo "  - key: \"读IOPS\"" >> "$OUTPUT_YAML"
		echo "    value: \"${read_iops:-未知}\"" >> "$OUTPUT_YAML"
		echo "    err: \"\"" >> "$OUTPUT_YAML"
		echo "  - key: \"写IOPS\"" >> "$OUTPUT_YAML"
		echo "    value: \"${write_iops:-未知}\"" >> "$OUTPUT_YAML"
		echo "    err: \"\"" >> "$OUTPUT_YAML"
		echo "  - key: \"读带宽\"" >> "$OUTPUT_YAML"
		echo "    value: \"${read_bw:-未知}\"" >> "$OUTPUT_YAML"
		echo "    err: \"\"" >> "$OUTPUT_YAML"
		echo "  - key: \"写带宽\"" >> "$OUTPUT_YAML"
		echo "    value: \"${write_bw:-未知}\"" >> "$OUTPUT_YAML"
		echo "    err: \"\"" >> "$OUTPUT_YAML"
	fi

	echo "" >> "$OUTPUT_YAML"
	log_info "磁盘性能检测完成"
}

# 6. IO错误检测（仅物理磁盘）
check_io_errors() {
	log_info "开始检测磁盘IO错误..."
	log_debug "执行命令: cat /proc/diskstats; dmesg | grep error"

	echo "io_errors_results:" >> "$OUTPUT_YAML"

	while IFS= read -r line; do
		local disk=$(echo "$line" | awk '{print $3}')
		if ! is_physical_disk "$disk"; then
			log_debug "跳过非物理磁盘的错误检测: $disk"
			continue
		fi
		local read_errors=$(echo "$line" | awk '{print $4}')
		local write_errors=$(echo "$line" | awk '{print $8}')
		local dmesg_errors=$(dmesg | tail -n 1000 | grep -i "$disk.*error" | wc -l)

		local status="正常"
		local err_msg=""
		if [ "$read_errors" -gt 0 ] || [ "$write_errors" -gt 0 ] || [ "$dmesg_errors" -gt 0 ]; then
			status="异常"
			err_msg="读: $read_errors, 写: $write_errors, 日志: $dmesg_errors"
			log_err "磁盘 $disk 检测到IO错误"
		fi

		echo "  - key: \"$disk\"" >> "$OUTPUT_YAML"
		echo "    value: \"$status\"" >> "$OUTPUT_YAML"
		echo "    err: \"$err_msg\"" >> "$OUTPUT_YAML"
	done < /proc/diskstats

	echo "" >> "$OUTPUT_YAML"
	log_info "磁盘IO错误检测完成"
}

# ========== Python渲染JSON结果函数（读取外部模板） ==========
render_json() {
	log_info "开始使用Python渲染JSON结果..."

	if [ ! -f "$JINJA_TEMPLATE_FILE" ]; then
		log_err "未找到Jinja模板文件: $JINJA_TEMPLATE_FILE"
		return 1
	fi

	if ! command -v python3 &> /dev/null; then
		log_err "未找到python3，无法生成JSON结果"
		return 1
	fi

	if ! python3 -c "import yaml, jinja2" &> /dev/null; then
		log_warn "未检测到pyyaml或jinja2库，尝试安装..."
		if ! pip3 install pyyaml jinja2 &> /dev/null; then
			log_err "安装依赖库失败，无法生成JSON结果"
			return 1
		fi
	fi

	python3 - << END
import yaml
from jinja2 import FileSystemLoader, Environment
import sys

try:
  env = Environment(loader=FileSystemLoader('.'))
  template = env.get_template("$JINJA_TEMPLATE_FILE")
  
  with open("$OUTPUT_YAML", "r") as f:
    data = yaml.safe_load(f)
  
  json_result = template.render(**data)
  
  with open("$OUTPUT_JSON", "w") as f:
    f.write(json_result)
  
  print("JSON渲染成功")
except Exception as e:
  print(f"JSON渲染失败: {str(e)}", file=sys.stderr)
  sys.exit(1)
END

	if [ $? -eq 0 ]; then
		log_info "JSON结果已保存至: $OUTPUT_JSON"
	else
		log_err "Python渲染JSON过程出错"
	fi
}

# ========== 主逻辑 ==========
declare -A CHECKS=(
	["disk_status"]=check_disk_status
	["disk_busy"]=check_disk_busy
	["ssd_lifetime"]=check_ssd_lifetime
	["ssd_interface_mode"]=check_ssd_interface_mode
	["disk_performance"]=check_disk_performance
	["io_errors"]=check_io_errors
)

selected_checks=("$@")

if [ ${#selected_checks[@]} -eq 0 ]; then
	log_warn "未指定检测项，将执行所有检查"
	selected_checks=("${!CHECKS[@]}")
fi

log_info "待执行的检查项: ${selected_checks[*]}"

for check in "${selected_checks[@]}"; do
	func=${CHECKS[$check]}
	if [ -n "$func" ]; then
		$func
		log_info "执行 $check 完成"
	else
		log_err "未知检测项: $check"
	fi
done

render_json

log_result "====== 磁盘检查任务执行完毕 ======"
log_result "检查结果已保存至:"
log_result "YAML: $OUTPUT_YAML"
log_result "JSON: $OUTPUT_JSON"
