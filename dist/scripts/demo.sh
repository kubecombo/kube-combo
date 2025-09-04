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

# 模拟 debug 信息
log_debug "这是一条 debug 信息"

# 模拟 info 信息
log_info "这是一条 info 信息"

# 模拟 warn 信息
log_warn "这是一条 warn 信息"

# 模拟 err 信息
log_err "这是一条 err 信息"

# 模拟 result 信息
log_result "这是一条 result 信息"
