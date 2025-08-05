#!/bin/bash

# 引入日志函数（假设你把日志函数放在 log.sh 中）
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# shellcheck disable=SC2034
# 设置日志级别为 debug
LOG_LEVEL=1

# shellcheck disable=SC2034
# 关闭文件日志
LOG_FLAG=false

# shellcheck disable=SC2034
# 设置日志文件位置
LOG_FILE="./demo.log"

# 模拟任务开始
log_info "开始执行任务..."

# 模拟 debug 信息
log_debug "当前执行路径为: $(pwd)"

# 模拟检查条件
if [ -f "/etc/passwd" ]; then
    log_info "/etc/passwd 文件存在"
else
    log_warn "/etc/passwd 文件不存在"
fi

# 模拟错误情况
command_not_found_output=$(non_existing_command 2>&1)
# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    log_err "命令执行失败：$command_not_found_output"
fi

# 模拟警告
log_warn "这是一个警告信息：磁盘空间不足"

# 模拟一直显示的日志
log_result "任务执行完毕，打印结果总览"
