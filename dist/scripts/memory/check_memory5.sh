#!/bin/bash

# 引入日志函数
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../log.sh"

# 获取当前时间（用于日志文件名，格式：202508041413）
log_timestamp=$(date +%Y%m%d%H%M)
# 脚本名称（不含路径和后缀）
script_name=$(basename "$0" .sh)

# 日志路径和文件名配置
LOG_DIR="/var/log/oneClickDetection/"
LOG_FILE="${LOG_DIR}${log_timestamp}-${script_name}.log"  # 格式：202508041413-memory_check.log

# 输出文件路径（当前路径）
OUTPUT_YAML="./${script_name}.yaml"
OUTPUT_JSON="./${script_name}.json"
# 同级目录的Jinja模板文件路径
JINJA_TEMPLATE_FILE="./check_memory.j2"  # 假设模板在同级目录

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
LOG_LEVEL=2       # 设置日志级别为 info
# shellcheck disable=SC2034
LOG_FLAG=true     # 开启文件日志

# 获取主机名和时间戳（YAML格式要求：yyyy:MM:dd HH:mm:ss）
hostname=$(hostname)
timestamp=$(date +"%Y:%m:%d %H:%M:%S")  # 符合要求的时间格式

log_info "====== 开始内存检查任务 ======"
log_debug "当前主机: $hostname"
log_debug "开始时间: $timestamp"
log_debug "日志文件路径: $LOG_FILE"
log_debug "输出YAML文件路径: $OUTPUT_YAML"
log_debug "输出JSON文件路径: $OUTPUT_JSON"
log_debug "Jinja模板文件路径: $JINJA_TEMPLATE_FILE"

# 初始化YAML文件
> "$OUTPUT_YAML"  # 清空文件
echo "nodename: $hostname" >> "$OUTPUT_YAML"
echo "timestamp: \"$timestamp\"" >> "$OUTPUT_YAML"
echo "" >> "$OUTPUT_YAML"

# ========== 实际检测函数（输出YAML格式片段） ==========
check_memory_frequency() {
	log_info "开始检查内存频率..."
	log_debug "执行命令: dmidecode -t memory"

	# 写入YAML分组标题
	echo "memory_frequency_results:" >> "$OUTPUT_YAML"

	# 解析内存频率信息并写入YAML
	dmidecode -t memory | awk -v file="$OUTPUT_YAML" -F: '
    /Locator/ {slot=$2; gsub(/^[ \t]+/, "", slot)}
    /Speed:/ && !/Configured/ {
      freq=$2; gsub(/^[ \t]+/, "", freq)
      if (freq != "Unknown" && freq != "") {
        if (slot == "") slot = "N/A"
        printf "  - key: %s\n    value: %s\n    err: \"\"\n", slot, freq >> file
      }
    }'

	echo "" >> "$OUTPUT_YAML" # 分组间空行
	log_info "内存频率检查完成"
}

check_memory_vendor() {
	log_info "开始检查内存厂商信息..."
	log_debug "执行命令: sudo dmidecode -t memory"

	# 写入YAML分组标题
	echo "memory_vendor_results:" >> "$OUTPUT_YAML"

	# 解析内存厂商信息并写入YAML
	sudo dmidecode -t memory | awk -v file="$OUTPUT_YAML" -F: '
    /Locator/ {slot=$2; gsub(/^[ \t]+/, "", slot)}
    /Manufacturer/ {
      vendor=$2; gsub(/^[ \t]+/, "", vendor)
      if (vendor ~ /[A-Za-z]/) {
        if (slot == "") slot = "N/A"
        printf "  - key: %s\n    value: %s\n    err: \"\"\n", slot, vendor >> file
      }
    }'

	echo "" >> "$OUTPUT_YAML" # 分组间空行
	log_info "内存厂商信息检查完成"
}

check_memory_rw_perf() {
	log_info "开始测试内存读写性能..."
	log_debug "执行命令: dd if=/dev/zero of=/tmp/testfile bs=1M count=256 conv=fdatasync"

	dd_output=$(dd if=/dev/zero of=/tmp/testfile bs=1M count=256 conv=fdatasync 2>&1)
	speed=$(echo "$dd_output" | grep copied | awk '{print $(NF-1)}')
	speed_unit=$(echo "$dd_output" | grep copied | awk '{print $NF}')
	rm -f /tmp/testfile

	# 写入YAML分组
	echo "memory_rw_perf_results:" >> "$OUTPUT_YAML"
	echo "  - key: Performance" >> "$OUTPUT_YAML"
	echo "    value: \"${speed} ${speed_unit}\"" >> "$OUTPUT_YAML"
	echo "    err: \"\"" >> "$OUTPUT_YAML"
	echo "" >> "$OUTPUT_YAML"

	log_debug "内存读写性能测试结果: $speed $speed_unit"
	log_info "内存读写性能测试完成"
}

check_memory_loose() {
	log_info "开始检查内存松动状态..."
	log_debug "检查文件: /var/log/mem_loose.log"

	# 初始化结果变量
	status="正常"
	err_msg=""

	if [ -s /var/log/mem_loose.log ]; then
		status="异常"
		err_msg="检测到松动，请检查 /var/log/mem_loose.log"
		log_warn "$err_msg"
	else
		log_info "内存松动状态检查正常"
	fi

	# 写入YAML分组
	echo "memory_loose_results:" >> "$OUTPUT_YAML"
	echo "  - key: Status" >> "$OUTPUT_YAML"
	echo "    value: $status" >> "$OUTPUT_YAML"
	echo "    err: \"$err_msg\"" >> "$OUTPUT_YAML"
	echo "" >> "$OUTPUT_YAML"
}

check_memory_size_check() {
	log_info "开始检查内存容量一致性..."
	current=$(free -g | awk '/Mem:/ {print $2}')
	log_debug "当前内存容量: ${current}G"

	# 初始化结果变量
	check_result="首次记录：${current}G"
	err_msg=""

	last=$(cat /var/log/mem_last_boot_size 2> /dev/null)
	if [ -z "$last" ]; then
		echo "$current" > /var/log/mem_last_boot_size
		log_info "$check_result"
	elif [ "$current" -lt "$last" ]; then
		check_result="异常，本次 ${current}G 小于上次 ${last}G"
		err_msg="$check_result"
		log_err "$err_msg"
	else
		check_result="一致（${current}G）"
		log_info "内存容量检查一致: ${current}G"
	fi

	# 写入YAML分组
	echo "memory_size_check_results:" >> "$OUTPUT_YAML"
	echo "  - key: Consistency" >> "$OUTPUT_YAML"
	echo "    value: \"$check_result\"" >> "$OUTPUT_YAML"
	echo "    err: \"$err_msg\"" >> "$OUTPUT_YAML"
	echo "" >> "$OUTPUT_YAML"
}

check_memory_usage() {
	log_info "开始检查内存使用率..."

	usage=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')

	# 确定状态和错误信息
	if [ "$usage" -lt 70 ]; then
		level="正常"
		err_msg=""
		log_info "内存使用率: ${usage}%（${level}）"
	elif [ "$usage" -lt 80 ]; then
		level="使用率高"
		err_msg=""
		log_info "内存使用率: ${usage}%（${level}）"
	elif [ "$usage" -lt 90 ]; then
		level="使用率较高"
		err_msg="$level"
		log_warn "内存使用率: ${usage}%（${level}）"
	else
		level="使用率非常高"
		err_msg="$level"
		log_err "内存使用率: ${usage}%（${level}）"
	fi

	# 写入YAML分组
	echo "memory_usage_results:" >> "$OUTPUT_YAML"
	echo "  - key: Usage" >> "$OUTPUT_YAML"
	echo "    value: \"${usage}%\"" >> "$OUTPUT_YAML"
	echo "    err: \"$err_msg\"" >> "$OUTPUT_YAML"
	echo "" >> "$OUTPUT_YAML"
}

# ========== Python渲染JSON结果函数（读取外部模板） ==========
render_json() {
	log_info "开始使用Python渲染JSON结果..."

	# 检查模板文件是否存在
	if [ ! -f "$JINJA_TEMPLATE_FILE" ]; then
		log_err "未找到Jinja模板文件: $JINJA_TEMPLATE_FILE"
		return 1
	fi

	# 检查Python是否安装
	if ! command -v python3 &> /dev/null; then
		log_err "未找到python3，无法生成JSON结果"
		return 1
	fi

	# 检查必要的Python库
	if ! python3 -c "import yaml, jinja2" &> /dev/null; then
		log_warn "未检测到pyyaml或jinja2库，尝试安装..."
		if ! pip3 install pyyaml jinja2 &> /dev/null; then
			log_err "安装依赖库失败，无法生成JSON结果"
			return 1
		fi
	fi

	# 使用Python读取外部模板并渲染JSON
	python3 - << END
import yaml
from jinja2 import FileSystemLoader, Environment
import sys

try:
  # 加载外部模板文件
  env = Environment(loader=FileSystemLoader('.'))  # 从当前目录加载模板
  template = env.get_template("$JINJA_TEMPLATE_FILE")
  
  # 读取YAML文件数据
  with open("$OUTPUT_YAML", "r") as f:
    data = yaml.safe_load(f)
  
  # 渲染模板并生成JSON
  json_result = template.render(**data)
  
  # 写入JSON文件
  with open("$OUTPUT_JSON", "w") as f:
    f.write(json_result)
  
  print("JSON渲染成功")
except Exception as e:
  print(f"JSON渲染失败: {str(e)}", file=sys.stderr)
  sys.exit(1)
END

	# 检查Python执行结果
	if [ $? -eq 0 ]; then
		log_info "JSON结果已保存至: $OUTPUT_JSON"
	else
		log_err "Python渲染JSON过程出错"
	fi
}

# ========== 主逻辑 ==========
declare -A CHECKS=(
	["memory_frequency"]=check_memory_frequency
	["memory_vendor"]=check_memory_vendor
	["memory_rw_perf"]=check_memory_rw_perf
	["memory_loose"]=check_memory_loose
	["memory_size"]=check_memory_size_check
	["memory_usage"]=check_memory_usage
)

selected_checks=("$@")

if [ ${#selected_checks[@]} -eq 0 ]; then
	log_warn "未指定检测项，将执行所有检查"
	selected_checks=("${!CHECKS[@]}")
fi

log_info "待执行的检查项: ${selected_checks[*]}"

# 执行选中的检查项
for check in "${selected_checks[@]}"; do
	func=${CHECKS[$check]}
	if [ -n "$func" ]; then
		$func
		log_info "执行 $check 完成"
	else
		log_err "未知检测项: $check"
	fi
done

# 调用Python渲染JSON结果（读取外部模板）
render_json

log_result "====== 内存检查任务执行完毕 ======"
log_result "检查结果已保存至:"
log_result "YAML: $OUTPUT_YAML"
log_result "JSON: $OUTPUT_JSON"
