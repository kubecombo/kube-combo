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
	"RAID_CARD_STATUS": {Script: "", Args: ""},

	// cpu
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

	// memory
	"MEMORY_FREQUENCY":              {Script: "/runAt/memory/check_memory5.sh", Args: ""},
	"MEMORY_MANUFACTURER":           {Script: "/runAt/memory/check_memory5.sh", Args: ""},
	"MEMORY_READ_WRITE_PERFORMANCE": {Script: "/runAt/memory/check_memory5.sh", Args: ""},
	"MEMORY_LOOSENING_ANOMALY":      {Script: "/runAt/memory/check_memory5.sh", Args: ""},
	"MEMORY_SIZE_ANOMALY":           {Script: "/runAt/memory/check_memory5.sh", Args: ""},
	"MEMORY_USAGE_RATE":             {Script: "/runAt/memory/check_memory5.sh", Args: ""},

	// basic disk function
	"DISK_STATUS":        {Script: "/runAt/basic-disk-function/check_disk2.sh", Args: ""},
	"DISK_BUSYNESS":      {Script: "/runAt/basic-disk-function/check_disk2.sh", Args: ""},
	"SSD_LIFESPAN":       {Script: "/runAt/basic-disk-function/check_disk2.sh", Args: ""},
	"SSD_INTERFACE_MODE": {Script: "/runAt/basic-disk-function/check_disk2.sh", Args: ""},
	"DISK_PERFORMANCE":   {Script: "/runAt/basic-disk-function/check_disk2.sh", Args: ""},
	"IO_ERROR":           {Script: "/runAt/basic-disk-function/check_disk2.sh", Args: ""},

	// system partition
	"DISK_USAGE": {Script: "/runAt/system-partition/system-partition.sh", Args: ""},

	// control node status
	"OFFLINE_CONTROL_NODE":                 {Script: "", Args: ""},
	"CONTROL_NODE_BASIC_COMPONENT":         {Script: "", Args: ""},
	"CLUSTER_TIME_SYNCHRONIZATION_SERVICE": {Script: "", Args: ""},
	"CONTROL_NODE_MANAGEMENT_SERVICE":      {Script: "", Args: ""},

	// network configuration
	"STORAGE_COMMUNICATION_NETWORK_PORT_CONNECTIVITY": {Script: "/runAt/network-configuration/storage-communication-network-port-connectivity.sh", Args: ""},
	"LINK_AGGREGATION_CONNECTIVITY":                   {Script: "/runAt/network-configuration/link-aggregation-connectivity.sh", Args: ""},
	"LATENCY":                                         {Script: "/runAt/network-configuration/latency-detection.sh", Args: ""},
	"IP_CONFLICT":                                     {Script: "/runAt/network-configuration/ip-conflict-detection.sh", Args: ""},
	"NEGOTIATED_RATE":                                 {Script: "/runAt/network-configuration/negotiated-rate.sh", Args: ""},
	"MTU_CONSISTENCY":                                 {Script: "/runAt/network-configuration/mtu-consistency.sh", Args: ""},
	"NETWORK_PORT_AGGREGATION_MODE_CONSISTENCY":       {Script: "/runAt/network-configuration/network-port-aggregation-mode-consistency-detection.sh", Args: ""},
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

func runTask(task Task, envVars map[string]string, timeout time.Duration) error {
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
		return err
	}
	if err != nil {
		klog.Errorf("Failed to run %s: %v, output: %s", task.Script, err, string(output))
		return err
	}

	klog.Infof("Output of %s:\n%s", task.Script, string(output))
	return nil
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
