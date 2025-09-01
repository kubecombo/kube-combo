package debugger

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type Metrics struct {
	Timestamp string              `json:"TIMESTAMP"`
	Tasks     map[string][]string `json:"Tasks"`
}

// Task 结构体
type Task struct {
	Script string
	Args   string
}

// 任务常量映射（直接用字符串作为 key）
var TaskMap = map[string]Task{
	// CPU 相关
	"CPU_MODEL":       {Script: "/runAt/demo.sh", Args: ""},
	"CPU_USAGE_RATE":  {Script: "check_cpu_usage.sh", Args: "--interval 5s"},
	"CPU_TEMPERATURE": {Script: "check_cpu_temperature.sh", Args: ""},
	"CPU_LOAD":        {Script: "check_cpu_load.sh", Args: "--avg 1"},

	// RAID
	"RAID_CARD_STATUS": {Script: "check_raid_card_status.sh", Args: ""},

	// 网络卡
	"NETWORK_PORT_PACKET_LOSS":     {Script: "check_network_port_packet_loss.sh", Args: "--count 10"},
	"NETWORK_PORT_CONNECTION_MODE": {Script: "check_network_port_connection_mode.sh", Args: ""},
	"FULL-DUPLEX_MODE":             {Script: "check_full_duplex_mode.sh", Args: ""},
	"NETWORK_PORT_SPEED":           {Script: "check_network_port_speed.sh", Args: ""},
	"NETWORK_CARD_CONFLICT":        {Script: "check_network_card_conflict.sh", Args: ""},
	"UNPLUGGED_AND_DISCONNECTION":  {Script: "check_unplugged_and_disconnection.sh", Args: ""},

	// 内存
	"MEMORY_FREQUENCY":              {Script: "check_memory_frequency.sh", Args: ""},
	"MEMORY_MANUFACTURER":           {Script: "check_memory_manufacturer.sh", Args: ""},
	"MEMORY_READ-WRITE_PERFORMANCE": {Script: "check_memory_read_write_performance.sh", Args: "--test 1G"},
	"MEMORY_LOOSENING_ANOMALY":      {Script: "check_memory_loosening_anomaly.sh", Args: ""},
	"MEMORY_SIZE_ANOMALY":           {Script: "check_memory_size_anomaly.sh", Args: ""},
	"MEMORY_USAGE_RATE":             {Script: "check_mem_usage.sh", Args: "--unit MB"},

	// 磁盘
	"DISK_STATUS":        {Script: "check_disk_status.sh", Args: ""},
	"DISK_BUSYNESS":      {Script: "check_disk_busyness.sh", Args: "--interval 5s"},
	"SSD_LIFESPAN":       {Script: "check_ssd_lifespan.sh", Args: ""},
	"SSD_INTERFACE_MODE": {Script: "check_ssd_interface_mode.sh", Args: ""},
	"DISK_PERFORMANCE":   {Script: "check_disk_performance.sh", Args: "--test sequential"},
	"IO_ERROR":           {Script: "check_io_error.sh", Args: ""},
	"DISK_USAGE":         {Script: "check_disk_usage.sh", Args: "/dev/sda1"},

	// 控制节点
	"OFFLINE_CONTROL_NODE":                 {Script: "check_offline_control_node.sh", Args: ""},
	"CONTROL_NODE_BASIC_COMPONENT":         {Script: "check_control_node_basic_component.sh", Args: ""},
	"CLUSTER_TIME_SYNCHRONIZATION_SERVICE": {Script: "check_cluster_time_synchronization.sh", Args: ""},
	"CONTROL_NODE_MANAGEMENT_SERVICE":      {Script: "check_control_node_management_service.sh", Args: ""},

	// 网络配置
	"STORAGE_COMMUNICATION_NETWORK_PORT_CONNECTIVITY": {Script: "check_storage_network_connectivity.sh", Args: ""},
	"LINK_AGGREGATION_CONNECTIVITY":                   {Script: "check_link_aggregation_connectivity.sh", Args: ""},
	"LATENCY":                                         {Script: "check_network_latency.sh", Args: "--ping-count 5"},
	"IP_CONFLICT":                                     {Script: "check_ip_conflict.sh", Args: ""},
	"NEGOTIATED_RATE":                                 {Script: "check_negotiated_rate.sh", Args: ""},
	"MTU_CONSISTENCY":                                 {Script: "check_mtu_consistency.sh", Args: ""},
	"NETWORK_PORT_AGGREGATION_MODE_CONSISTENCY":       {Script: "check_port_aggregation_mode_consistency.sh", Args: ""},
}

func loadMetrics(filePath string) (*Metrics, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open file: %v", err)
	}
	defer f.Close()

	var m Metrics
	decoder := json.NewDecoder(f)
	if err := decoder.Decode(&m); err != nil {
		return nil, fmt.Errorf("failed to decode json: %v", err)
	}

	return &m, nil
}

func runTask(task Task, envVars map[string]string) error {
	args := []string{}
	if task.Args != "" {
		args = strings.Fields(task.Args)
	}

	cmd := exec.Command(task.Script, args...)
	cmd.Env = os.Environ()
	for k, v := range envVars {
		cmd.Env = append(cmd.Env, fmt.Sprintf("%s=%s", k, v))
	}
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to run %s: %v, output: %s", task.Script, err, string(output))
	}

	fmt.Printf("Output of %s:\n%s\n", task.Script, string(output))
	return nil
}
