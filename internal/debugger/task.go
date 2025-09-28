package debugger

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"k8s.io/klog/v2"
)

type Detection struct {
	Timestamp string              `json:"TIMESTAMP"`
	Tasks     map[string][]string `json:"Tasks"`
}

// Task Structure
type Task struct {
	Script string
	Args   string
}

// Task constant mapping
var TaskMap = map[string]Task{
	// raid
	"RAID_CARD_STATUS": {Script: "/runAt/raid/check_raid.sh", Args: ""},

	/* // cpu
	"CPU_MODEL":       {Script: "/runAt/cpu/CPU_Detection.sh", Args: ""},
	"CPU_USAGE_RATE":  {Script: "/runAt/cpu/CPU_Detection.sh", Args: ""},
	"CPU_TEMPERATURE": {Script: "/runAt/cpu/CPU_Detection.sh", Args: ""},
	"CPU_LOAD":        {Script: "/runAt/cpu/CPU_Detection.sh", Args: ""},

	// network card
	"NETWORK_PORT_PACKET_LOSS":     {Script: "/runAt/network-card/network-port-packet-loss-detection.sh", Args: ""},
	"NETWORK_PORT_CONNECTION_MODE": {Script: "/runAt/network-card/network-port-connection-mode-detection.sh", Args: ""},
	"FULL_DUPLEX_MODE":             {Script: "/runAt/network-card/full-duplex-mode-detection.sh", Args: ""},
	"NETWORK_PORT_SPEED":           {Script: "/runAt/network-card/network-port-speed-detection.sh", Args: ""},
	"NETWORK_CARD_CONFLICT":        {Script: "/runAt/network-card/network-card-conflict-detection.sh", Args: ""},
	"UNPLUGGED_AND_DISCONNECTION":  {Script: "/runAt/network-card/unplugged-and-disconnection-detection.sh", Args: ""},
	*/

	// memory
	"MEMORY_FREQUENCY":              {Script: "/runAt/memory/memory_frequency.sh", Args: ""},
	"MEMORY_MANUFACTURER":           {Script: "/runAt/memory/memory_looseness.sh", Args: ""},
	"MEMORY_READ_WRITE_PERFORMANCE": {Script: "/runAt/memory/memory_rw_perf.sh", Args: ""},
	// "MEMORY_LOOSENING_ANOMALY":      {Script: "/runAt/memory/memory_looseness.sh", Args: ""},
	"MEMORY_SIZE_ANOMALY": {Script: "/runAt/memory/memory_size.sh", Args: ""},
	"MEMORY_USAGE_RATE":   {Script: "/runAt/memory/memory_usage.sh", Args: ""},

	/* // basic disk function
	"DISK_STATUS":        {Script: "/runAt/basic-disk-function/disk_status.sh", Args: ""},
	"DISK_BUSYNESS":      {Script: "/runAt/basic-disk-function/disk_busy.sh", Args: ""},
	// "SSD_LIFESPAN":       {Script: "/runAt/basic-disk-function/disk_ssd_lifetime.sh", Args: ""},
	"SSD_INTERFACE_MODE": {Script: "/runAt/basic-disk-function/disk_ssd_interface_mode.sh", Args: ""},
	"DISK_PERFORMANCE":   {Script: "/runAt/basic-disk-function/disk_performance.sh", Args: ""},
	// "IO_ERROR":           {Script: "/runAt/basic-disk-function/disk_io_errors.sh", Args: ""},

	// system partition
	"DISK_USAGE": {Script: "/runAt/system-partition/system-partition.sh", Args: ""},

	// control node status
	"OFFLINE_CONTROL_NODE":                 {Script: "/runAt/control-node-status/check_node_status.sh", Args: ""},
	"CONTROL_NODE_BASIC_COMPONENT":         {Script: "/runAt/control-node-status/check_base_components.sh", Args: ""},
	"CLUSTER_TIME_SYNCHRONIZATION_SERVICE": {Script: "/runAt/control-node-status/check_time_synchronization.sh", Args: ""},
	"CONTROL_NODE_MANAGEMENT_SERVICE":      {Script: "/runAt/control-node-status/check_management_services.sh", Args: ""},

	// network configuration
	"STORAGE_COMMUNICATION_NETWORK_PORT_CONNECTIVITY": {Script: "/runAt/network-configuration/storage-communication-network-port-connectivity.sh", Args: ""},
	"LINK_AGGREGATION_CONNECTIVITY":                   {Script: "/runAt/network-configuration/link-aggregation-connectivity.sh", Args: ""},
	"LATENCY":                                         {Script: "/runAt/network-configuration/latency-detection.sh", Args: ""},
	"IP_CONFLICT":                                     {Script: "/runAt/network-configuration/ip-conflict-detection.sh", Args: ""},
	"NEGOTIATED_RATE":                                 {Script: "/runAt/network-configuration/negotiated-rate.sh", Args: ""},
	"MTU_CONSISTENCY":                                 {Script: "/runAt/network-configuration/mtu-consistency.sh", Args: ""},
	"NETWORK_PORT_AGGREGATION_MODE_CONSISTENCY":       {Script: "/runAt/network-configuration/network-port-aggregation-mode-consistency-detection.sh", Args: ""}, */
}

func loadDetection(filePath string) (*Detection, error) {
	f, err := os.Open(filePath)
	if err != nil {
		klog.Errorf("Failed to open file %s: %v", filePath, err)
		return nil, err
	}
	defer f.Close()

	var d Detection
	decoder := json.NewDecoder(f)
	if err := decoder.Decode(&d); err != nil {
		klog.Errorf("Failed to decode JSON: %v", err)
		return nil, err
	}

	return &d, nil
}

func runTask(task Task, envVars map[string]string, timeout time.Duration) (int, error) {
	args := []string{}
	if task.Args != "" {
		args = strings.Fields(task.Args)
	}

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, task.Script, args...)
	cmd.Env = append(os.Environ(), formatEnv(envVars)...)

	output, err := cmd.CombinedOutput()
	if ctx.Err() == context.DeadlineExceeded {
		klog.Errorf("Task %s timed out after %s", task.Script, timeout)
		return 1, fmt.Errorf("task timed out after %s", timeout)
	}
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			code := exitErr.ExitCode()
			// post failed
			if code == 100 {
				klog.Warningf("Task %s exited with code 100, post result failed. Output:\n%s", task.Script, string(output))
				return 100, fmt.Errorf("task exited with code %d, output:\n%s", code, string(output))
			} else {
				klog.Errorf("Task %s exited with code %d, output:\n%s", task.Script, code, string(output))
				return 1, fmt.Errorf("task exited with code %d, output:\n%s", code, string(output))
			}
		}

		// other fails
		klog.Errorf("Failed to run %s: %v, output:\n%s", task.Script, err, string(output))
		return 1, fmt.Errorf("failed to run %s: %w, output:\n%s", task.Script, err, string(output))
	}

	klog.Infof("Output of %s:\n%s", task.Script, string(output))
	return 0, nil
}

func formatEnv(env map[string]string) []string {
	result := make([]string, 0, len(env))
	for k, v := range env {
		result = append(result, fmt.Sprintf("%s=%s", k, v))
	}
	return result
}

// CountValidTasks
func CountValidTasks(tasks map[string][]string) int {
	validCount := 0

	for category, taskNames := range tasks {
		for _, taskName := range taskNames {
			if _, ok := TaskMap[taskName]; ok {
				validCount++
			} else {
				klog.Warningf("[%s: %s] Task mapping not found", category, taskName)
			}
		}
	}

	klog.Infof("Total valid tasks: %d", validCount)
	return validCount
}

type StartFlag struct {
	NodeName  string `json:"nodeName"`
	JobCount  string `json:"jobcount"`
	Timestamp string `json:"timestamp"`
}

func BuildStartFlag(nodeName string, jobCount int, timestamp string) (string, error) {
	data := StartFlag{
		NodeName:  nodeName,
		JobCount:  fmt.Sprintf("%d", jobCount), // 转为字符串
		Timestamp: timestamp,                   // 时间戳（秒）
	}
	bytes, err := json.Marshal(data)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

type FinishFlag struct {
	NodeName  string `json:"nodeName"`
	Terminate string `json:"terminate"`
	Timestamp string `json:"timestamp"`
}

func BuildFinishFlag(nodeName string, timestamp string) (string, error) {
	data := FinishFlag{
		NodeName:  nodeName,
		Terminate: "true",
		Timestamp: timestamp,
	}

	bytes, err := json.Marshal(data)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

// NodeReport
type NodeReport struct {
	NodeName  string                       `json:"NodeName"`
	Timestamp string                       `json:"Timestamp"`
	Checks    map[string]map[string]string `json:"Checks"` // 每个检测项只有一条 status
}

// BuildNodeReport
func BuildNodeReport(nodeName string, timestamp string, checks map[string][]map[string]string) (string, error) {
	report := make(map[string]interface{})
	report["NodeName"] = nodeName

	for k, v := range checks {
		report[k] = v
	}

	report["Timestamp"] = timestamp

	data, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}
