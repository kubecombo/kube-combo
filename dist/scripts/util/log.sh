#!/bin/bash

# 日志级别 debug-1, info-2, warn-3, error-4, result-5
# 默认配置
# : "${LOG_LEVEL:=info}"    # 默认 info
# : "${LOG_FLAG:=false}" # 默认关闭文件日志
# : "${LOG_FILE:=./log}" # 默认日志文件位置

case "$LOG_LEVEL" in
    debug | DEBUG) level_num=1 ;;
    info | INFO) level_num=2 ;;
    warn | WARN) level_num=3 ;;
    error | ERROR) level_num=4 ;;
    result | RESULT) level_num=5 ;;
    *) level_num=2 ;; # 默认 info
esac

# 调试日志
function log_debug() {
    # shellcheck disable=SC2124
    content="[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $@"
    [ "$LOG_FLAG" == "true" ] && echo "$content" >>"$LOG_FILE" || true
    [ "$level_num" -le 1 ] && echo -e "\033[90m" "${content}" "\033[0m" || true
}

# 信息日志
function log_info() {
    # shellcheck disable=SC2124
    content="[INFO] $(date '+%Y-%m-%d %H:%M:%S') $@"
    [ "$LOG_FLAG" == "true" ] && echo "$content" >>"$LOG_FILE" || true
    [ "$level_num" -le 2 ] && echo -e "\033[32m" "${content}" "\033[0m" || true
}

# 警告日志
function log_warn() {
    # shellcheck disable=SC2124
    content="[WARN] $(date '+%Y-%m-%d %H:%M:%S') $@"
    [ "$LOG_FLAG" == "true" ] && echo "$content" >>"$LOG_FILE" || true
    [ "$level_num" -le 3 ] && echo -e "\033[33m" "${content}" "\033[0m" || true
}

# 错误日志
function log_err() {
    # shellcheck disable=SC2124
    content="[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $@"
    [ "$LOG_FLAG" == "true" ] && echo "$content" >>"$LOG_FILE" || true
    [ "$level_num" -le 4 ] && echo -e "\033[31m" "${content}" "\033[0m" || true
}

# 打印脚本执行结果总览
function log_result() {
    # shellcheck disable=SC2124
    content="[RESULT] $(date '+%Y-%m-%d %H:%M:%S') $@"
    [ "$LOG_FLAG" == "true" ] && echo "$content" >>"$LOG_FILE" || true
    [ "$level_num" -le 5 ] && echo -e "\033[36m" "${content}" "\033[0m" || true
}

# 打印文件日志
function log_file() {
    if [ -s "$TMP_INFO" ] && [ -n "$(cat "$TMP_INFO")" ]; then
        while IFS= read -r info; do
            log_info "$info"
        done <"$TMP_INFO"
    fi
    if [ -s "$TMP_ERR" ] && [ -n "$(cat "$TMP_ERR")" ]; then
        while IFS= read -r err; do
            log_err "$err"
        done <"$TMP_ERR"
    fi
}
