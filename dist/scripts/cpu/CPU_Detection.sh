#!/bin/bash
# 综合CPU监控脚本：修复物理CPU核心分配异常 + 整合全功能
# 功能覆盖：CPU型号识别、物理CPU使用率（精准核心映射）、CPU温度、频率占比、1/5/15分钟负载
# 输出格式：统一YAML文件（含监控时间、主机信息、异常告警）

# -------------------------- 全局核心配置 --------------------------
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
OUTPUT_YAML="comprehensive_cpu_monitor.yaml"  # 统一输出YAML文件名
SAMPLE_INTERVAL=0.1                             # CPU使用率采样间隔（秒）
PROM_NAMESPACE="monitoring"                    # Prometheus命名空间
PROM_SERVICE="cmss-ekiplus-prometheus-system"  # Prometheus服务名
INSTANCE=""                                    # K8s主机Instance名

# -------------------------- 工具函数：初始化YAML文件 --------------------------
initialize_yaml() {
    > "$OUTPUT_YAML"  # 清空旧文件
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')" >> "$OUTPUT_YAML"
    echo "NodeName: $(hostname) " >> "$OUTPUT_YAML"
    echo "" >> "$OUTPUT_YAML"
    echo "===== 初始化完成，输出文件：$(pwd)/$OUTPUT_YAML ====="
}

# -------------------------- 模块1：本地CPU监控（型号 + 精准物理CPU使用率） --------------------------
collect_local_cpu_metrics() {
    echo -e "\n===== 模块1：本地CPU型号与精准物理CPU使用率监控 ====="

    # 1.1 获取CPU型号信息
    echo "1.1 读取CPU硬件型号..."
    vendor_id=$(grep -m1 'vendor_id' /proc/cpuinfo | awk -F': ' '{print $2}')
    cpu_model=$(grep -m1 'model name' /proc/cpuinfo | awk -F': ' '{print $2}')
    echo "cpu_model_results:" >> "$OUTPUT_YAML"
    echo "  - key: $vendor_id" >> "$OUTPUT_YAML"
    echo "    value: \"$cpu_model\"" >> "$OUTPUT_YAML"
    echo "    err: \"\"" >> "$OUTPUT_YAML"
    echo "" >> "$OUTPUT_YAML"

    # 1.2 修复版：精准识别物理CPU与专属核心映射
    echo "1.2 识别物理CPU数量与专属核心分配..."
    physical_ids=$(grep '^physical id' /proc/cpuinfo | awk '{print $4}' | sort -n | uniq)
    declare -A phys_core_map  # 存储物理CPU与核心的映射关系

    # 遍历每个物理CPU，抓取其对应的所有核心
    for phys_id in $physical_ids; do
        core_list=$(awk -v target_pid="$phys_id" '
            /^physical id/ {
                current_pid = $4;
                is_target = (current_pid == target_pid) ? 1 : 0;
            }
            is_target && /^processor/ {
                print $3;
            }
        ' /proc/cpuinfo | tr '\n' ' ')
        
        phys_core_map[$phys_id]="$core_list"
    done

    # 异常处理：未检测到物理CPU信息
    if [ ${#phys_core_map[@]} -eq 0 ]; then
        echo "❌ 错误：无法从/proc/cpuinfo读取物理CPU信息"
        echo "cpu_usage_results:" >> "$OUTPUT_YAML"
        echo "  - key: Error" >> "$OUTPUT_YAML"
        echo "    value: \"物理CPU识别失败\"" >> "$OUTPUT_YAML"
        echo "    err: \"/proc/cpuinfo无physical id字段，可能为虚拟环境\"" >> "$OUTPUT_YAML"
        echo "" >> "$OUTPUT_YAML"
        return 1
    fi

    # 打印物理CPU与核心的映射关系（验证修复效果）
    echo "✅ 成功识别：${#phys_core_map[@]} 个物理CPU"
    for phys_id in "${!phys_core_map[@]}"; do
        echo "  物理CPU$phys_id 专属核心：${phys_core_map[$phys_id]}"
    done

    # 1.3 物理CPU使用率计算函数（基于专属核心）
    calc_physical_cpu_usage() {
        local phys_id=$1
        local cores=$2
        local user1=0 nice1=0 system1=0 idle1=0
        local user2=0 nice2=0 system2=0 idle2=0

        # 第一次采样
        for core in $cores; do
            read -r u n s i <<< $(grep "cpu$core" /proc/stat | awk '{print $2, $3, $4, $5}')
            user1=$((user1 + u))
            nice1=$((nice1 + n))
            system1=$((system1 + s))
            idle1=$((idle1 + i))
        done

        sleep $SAMPLE_INTERVAL  # 采样间隔

        # 第二次采样
        for core in $cores; do
            read -r u n s i <<< $(grep "cpu$core" /proc/stat | awk '{print $2, $3, $4, $5}')
            user2=$((user2 + u))
            nice2=$((nice2 + n))
            system2=$((system2 + s))
            idle2=$((idle2 + i))
        done

        # 计算使用率
        local user_diff=$((user2 - user1))
        local nice_diff=$((nice2 - nice1))
        local system_diff=$((system2 - system1))
        local idle_diff=$((idle2 - idle1))
        local total_diff=$((user_diff + nice_diff + system_diff + idle_diff))
        local usage=0
        [ $total_diff -ne 0 ] && usage=$(( (total_diff - idle_diff) * 100 / total_diff ))

        # 告警判断
        local err=""
        [ $usage -ge 90 ] && err="CPU使用率过高（≥90%）"

        # 输出YAML片段
        echo "  - key: PhysicalCPU$phys_id"
        echo "    value: \"$usage%\""
        echo "    err: \"$err\""
    }

    # 1.4 批量计算使用率并写入YAML
    echo -e "\n1.3 计算各物理CPU使用率（采样间隔：${SAMPLE_INTERVAL}s）..."
    echo "cpu_usage_results:" >> "$OUTPUT_YAML"
    for phys_id in $physical_ids; do
        cores=${phys_core_map[$phys_id]}
        echo "  正在监控 PhysicalCPU$phys_id（专属核心：$cores）..."
        single_cpu_yaml=$(calc_physical_cpu_usage "$phys_id" "$cores")
        echo "$single_cpu_yaml" >> "$OUTPUT_YAML"
    done
    echo "" >> "$OUTPUT_YAML"
    echo "✅ 模块1完成"
}

# -------------------------- 模块2：Prometheus关联监控（温度/频率/负载） --------------------------
collect_prometheus_metrics() {
    echo -e "\n===== 模块2：Prometheus关联监控 ====="

    # 2.1 初始化Prometheus依赖
    echo "2.1 初始化Prometheus环境..."
    # 获取K8s Instance名
    INSTANCE=$(kubectl get node $(hostname) -o jsonpath='{.metadata.name}' 2>/dev/null)
    if [ -z "$INSTANCE" ]; then
        local err_msg="kubectl无法获取节点名，无权限或非K8s环境"
        echo "❌ 错误：$err_msg"
        # 写入错误YAML
        echo "cpu_temp_results:" >> "$OUTPUT_YAML"
        echo "  - key: Error" >> "$OUTPUT_YAML"
        echo "    value: \"Instance获取失败\"" >> "$OUTPUT_YAML"
        echo "    err: \"$err_msg\"" >> "$OUTPUT_YAML"
        echo "" >> "$OUTPUT_YAML"

        echo "CPUFrequencyHigh_results:" >> "$OUTPUT_YAML"
        echo "  - key: Error" >> "$OUTPUT_YAML"
        echo "    value: \"Instance获取失败\"" >> "$OUTPUT_YAML"
        echo "    err: \"$err_msg\"" >> "$OUTPUT_YAML"
        echo "" >> "$OUTPUT_YAML"

        echo "CPUload1_results:" >> "$OUTPUT_YAML"
        echo "  - key: Error" >> "$OUTPUT_YAML"
        echo "    value: \"Instance获取失败\"" >> "$OUTPUT_YAML"
        echo "    err: \"$err_msg\"" >> "$OUTPUT_YAML"
        echo "" >> "$OUTPUT_YAML"
        return 1
    fi

    # 获取Prometheus IP
    PROM_IP=$(kubectl get svc -n $PROM_NAMESPACE $PROM_SERVICE -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -z "$PROM_IP" ]; then
        local err_msg="Prometheus服务（$PROM_NAMESPACE/$PROM_SERVICE）不存在或无权限"
        echo "❌ 错误：$err_msg"
        # 写入错误YAML
        echo "cpu_temp_results:" >> "$OUTPUT_YAML"
        echo "  - key: Error" >> "$OUTPUT_YAML"
        echo "    value: \"Prometheus IP获取失败\"" >> "$OUTPUT_YAML"
        echo "    err: \"$err_msg\"" >> "$OUTPUT_YAML"
        echo "" >> "$OUTPUT_YAML"

        echo "CPUFrequencyHigh_results:" >> "$OUTPUT_YAML"
        echo "  - key: Error" >> "$OUTPUT_YAML"
        echo "    value: \"Prometheus IP获取失败\"" >> "$OUTPUT_YAML"
        echo "    err: \"$err_msg\"" >> "$OUTPUT_YAML"
        echo "" >> "$OUTPUT_YAML"

        echo "CPUload1_results:" >> "$OUTPUT_YAML"
        echo "  - key: Error" >> "$OUTPUT_YAML"
        echo "    value: \"Prometheus IP获取失败\"" >> "$OUTPUT_YAML"
        echo "    err: \"$err_msg\"" >> "$OUTPUT_YAML"
        echo "" >> "$OUTPUT_YAML"
        return 1
    fi
    echo "  主机Instance: $INSTANCE"
    echo "  Prometheus IP: $PROM_IP"

    # 定义Prometheus API地址
    PROM_ALERTS_URL="http://$PROM_IP:9090/api/v1/alerts"
    PROM_RULES_URL="http://$PROM_IP:9090/api/v1/rules"
    PROM_METRIC_URL="http://$PROM_IP:9090/api/v1/query"

    # 2.2 CPU温度监控
    echo -e "\n2.2 CPU温度监控..."
    local TEMP_ALERT="IPMICPUTemperatureCritical"
    local TEMP_QUERY="max by (SensorName) (last_over_time(ipmi_sensor_status{SensorID=\"processor\",SensorName=~\"(?i)^cpu(?:[ _-]*[0-9]+)?(?:[ _-]*(?:core(?:[ _-]*rem)?))?(?:[ _-]*(?:temp|temperature))?(?:[ _-]*[0-9]+)?$\",target=\"$INSTANCE\",SensorStatus!=\"N/A\",SensorType=\"Temperature\"}[10m]))"
    
    # 获取告警信息
    local ALERTS_RESP=$(curl -s "$PROM_ALERTS_URL")
    local RULES_RESP=$(curl -s "$PROM_RULES_URL")
    local RULE_EXISTS=$(echo "$RULES_RESP" | jq -r --arg a "$TEMP_ALERT" '.data.groups[].rules[] | select(.name==$a) | .name' | grep -c "$TEMP_ALERT")
    local ALERT_INFO=""
    [ "$RULE_EXISTS" -gt 0 ] && ALERT_INFO=$(echo "$ALERTS_RESP" | jq -r --arg a "$TEMP_ALERT" --arg t "$INSTANCE" '.data.alerts[] | select(.labels.alertname==$a and .labels.target==$t and .state=="firing") | "\(.labels.SensorName)|\(.annotations.description)"' | sed -E 's/\([^)]*\)//g; s/  +/ /g; s/ $//')

    # 写入温度YAML
    echo "cpu_temp_results:" >> "$OUTPUT_YAML"
    local QUERY_RESP=$(curl -s "$PROM_METRIC_URL" --data-urlencode "query=$TEMP_QUERY")
    if [ -n "$(echo "$QUERY_RESP" | jq -r '.data.result[]')" ]; then
        echo "$QUERY_RESP" | jq -r '.data.result[] | @base64' | while read -r ITEM; do
            local SENSOR=$(echo "$ITEM" | base64 -d | jq -r '.metric.SensorName')
            local VAL=$(echo "$ITEM" | base64 -d | jq -r '.value[1]')
            local ERR=$(echo "$ALERT_INFO" | grep "^$SENSOR|" | cut -d'|' -f2- || echo "")
            echo "  - key: $SENSOR" >> "$OUTPUT_YAML"
            echo "    value: \"$VAL\"" >> "$OUTPUT_YAML"
            echo "    err: \"$ERR\"" >> "$OUTPUT_YAML"
        done
    else
        echo "  - key: NoData" >> "$OUTPUT_YAML"
        echo "    value: \"无温度数据\"" >> "$OUTPUT_YAML"
        echo "    err: \"IPMI传感器未启用或Prometheus未采集\"" >> "$OUTPUT_YAML"
    fi
    echo "" >> "$OUTPUT_YAML"
    echo "✅ 2.2 温度监控完成"

    # 2.3 CPU频率占比监控
    echo -e "\n2.3 CPU频率占比监控..."
    local FREQ_ALERT="CPUFrequencyHigh"
    local FREQ_QUERY="node_cpu_scaling_frequency_hertz / node_cpu_scaling_frequency_max_hertz{instance=\"$INSTANCE\"}"
    
    # 获取告警信息
    ALERTS_RESP=$(curl -s "$PROM_ALERTS_URL")
    RULES_RESP=$(curl -s "$PROM_RULES_URL")
    RULE_EXISTS=$(echo "$RULES_RESP" | jq -r --arg a "$FREQ_ALERT" '.data.groups[].rules[] | select(.name==$a) | .name' | grep -c "$FREQ_ALERT")
    ALERT_INFO=""
    [ "$RULE_EXISTS" -gt 0 ] && ALERT_INFO=$(echo "$ALERTS_RESP" | jq -r --arg a "$FREQ_ALERT" --arg i "$INSTANCE" '.data.alerts[] | select(.labels.alertname==$a and .labels.instance==$i and .state=="firing") | "cpu\(.labels.cpu)|\(.annotations.description)"' | sed -E 's/\([^)]*\)//g')

    # 写入频率YAML
    echo "CPUFrequencyHigh_results:" >> "$OUTPUT_YAML"
    QUERY_RESP=$(curl -s "$PROM_METRIC_URL" --data-urlencode "query=$FREQ_QUERY")
    if [ -n "$(echo "$QUERY_RESP" | jq -r '.data.result[]')" ]; then
        echo "$QUERY_RESP" | jq -r '.data.result[] | @base64' | while read -r ITEM; do
            local RAW_CPU=$(echo "$ITEM" | base64 -d | jq -r '.metric.cpu')
            local CPU_KEY="cpu$RAW_CPU"
            local FREQ_RATIO=$(echo "$ITEM" | base64 -d | jq -r '.value[1]')
            local ERR=$(echo "$ALERT_INFO" | grep "^$CPU_KEY|" | cut -d'|' -f2- || echo "")
            echo "  - key: $CPU_KEY" >> "$OUTPUT_YAML"
            echo "    value: \"$FREQ_RATIO\"" >> "$OUTPUT_YAML"
            echo "    err: \"$ERR\"" >> "$OUTPUT_YAML"
        done
    else
        echo "  - key: NoData" >> "$OUTPUT_YAML"
        echo "    value: \"无频率数据\"" >> "$OUTPUT_YAML"
        echo "    err: \"Prometheus未采集频率指标\"" >> "$OUTPUT_YAML"
    fi
    echo "" >> "$OUTPUT_YAML"
    echo "✅ 2.3 频率监控完成"

    # 2.4 CPU负载监控（1/5/15分钟）
    echo -e "\n2.4 CPU负载监控..."
    local ALERTS=("HighCPULoad1Min" "HighCPULoad5Min" "HighCPULoad15Min")
    local METRICS=("node_load1" "node_load5" "node_load15")
    local RESULT_GROUPS=("CPUload1_results" "CPUload5_results" "CPUload15_results")
    declare -a ALERT_DESCS=()
    declare -a METRIC_VALS=()

    # 批量获取负载数据
    for i in "${!ALERTS[@]}"; do
        local ALERT="${ALERTS[$i]}"
        local METRIC="${METRICS[$i]}"
        echo "  处理 $ALERT（指标：$METRIC）..."
        
        # 检查告警规则是否存在
        local RULE_EXISTS=$(echo "$(curl -s "$PROM_RULES_URL")" | jq -r --arg a "$ALERT" '.data.groups[].rules[] | select(.name==$a) | .name' | grep -c "$ALERT")
        if [ "$RULE_EXISTS" -eq 0 ]; then
            ALERT_DESCS[$i]="告警规则 $ALERT 不存在"
            METRIC_VALS[$i]="获取失败（无规则）"
            continue
        fi

        # 检查firing告警
        local ALERT_RESP=$(curl -s "$PROM_ALERTS_URL")
        local FIRING_COUNT=$(echo "$ALERT_RESP" | jq -r --arg a "$ALERT" --arg i "$INSTANCE" '.data.alerts[] | select(.labels.alertname==$a and .labels.instance==$i and .state=="firing") | .state' | grep -c "firing")
        
        if [ "$FIRING_COUNT" -gt 0 ]; then
            # 有告警时获取描述和指标值
            local ALERT_DESC=$(echo "$ALERT_RESP" | jq -r --arg a "$ALERT" --arg i "$INSTANCE" '.data.alerts[] | select(.labels.alertname==$a and .labels.instance==$i and .state=="firing") | .annotations.description' | head -n 1 | sed -E 's/\([^)]*\)//g; s/  +/ /g; s/ $//')
            local METRIC_VAL=$(curl -s "$PROM_METRIC_URL" --data-urlencode "query=${METRIC}{instance=\"$INSTANCE\"}" | jq -r '.data.result[0].value[1] // "获取失败"')
            ALERT_DESCS[$i]="$ALERT_DESC"
            METRIC_VALS[$i]="$METRIC_VAL"
        else
            # 无告警时直接获取指标值
            local METRIC_VAL=$(curl -s "$PROM_METRIC_URL" --data-urlencode "query=${METRIC}{instance=\"$INSTANCE\"}" | jq -r '.data.result[0].value[1] // "获取失败"')
            ALERT_DESCS[$i]=""
            METRIC_VALS[$i]="$METRIC_VAL"
        fi
    done

    # 写入负载YAML
    for i in "${!METRICS[@]}"; do
        local GROUP="${RESULT_GROUPS[$i]}"
        local METRIC="${METRICS[$i]}"
        local VAL="${METRIC_VALS[$i]}"
        local ERR="${ALERT_DESCS[$i]}"
        
        echo "${GROUP}:" >> "$OUTPUT_YAML"
        echo "  - key: ${METRIC}" >> "$OUTPUT_YAML"
        echo "    value: \"${VAL}\"" >> "$OUTPUT_YAML"
        echo "    err: \"${ERR}\"" >> "$OUTPUT_YAML"
        echo "" >> "$OUTPUT_YAML"
    done
    echo "✅ 2.4 负载监控完成"
    echo "✅ 模块2完成"
}

# -------------------------- 主程序入口 --------------------------
echo "===== 综合CPU监控脚本启动 ====="
initialize_yaml
collect_local_cpu_metrics
collect_prometheus_metrics
echo -e "\n===== 所有监控任务完成 ====="
echo "最终监控结果已保存至：$(pwd)/$OUTPUT_YAML"
