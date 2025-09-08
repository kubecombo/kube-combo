package debugger

import (
	"os"
	"path/filepath"
	"time"

	"github.com/kubecombo/kube-combo/internal/util"
	"k8s.io/klog/v2"
)

func StartDebugger(config *Configuration, stopCh <-chan struct{}) {
	if config.TaskFile == "" {
		klog.Error("TaskFile is not specified")
		return
	}

	taskFilePath := filepath.Join(config.TaskFilePath, config.TaskFile)
	if err := util.CheckFileExistence(taskFilePath); err != nil {
		klog.Error(err)
		return
	}
	klog.Info("TaskFile exists:", taskFilePath)

	detection, err := loadDetection(taskFilePath)
	if err != nil {
		klog.Error(err)
		return
	}

	varEnv := map[string]string{}
	if detection.Timestamp != "" {
		varEnv["timestamp"] = detection.Timestamp
	}

	validCount := CountValidTasks(detection.Tasks)
	klog.Infof("Post valid tasks: %d", validCount)

	nodeName := os.Getenv("NODE_NAME")
	if nodeName == "" {
		klog.Error("NODE_NAME not set")
	} else {
		klog.Infof("NODE_NAME=%s\n", nodeName)
	}

	klog.Infof("At timestamp=%s, node=%s starts %d tasks", detection.Timestamp, nodeName, validCount)
	jsonStr, err := BuildStartFlag(nodeName, validCount, varEnv["timestamp"])
	if err != nil {
		klog.Error(err)
	}
	klog.Info(jsonStr)
	// TODO: post valid task numbers and begin time

	successCount := 0
	failCount := 0

	for category, taskNames := range detection.Tasks {
		for _, taskName := range taskNames {
			task, ok := TaskMap[taskName]
			if !ok {
				klog.Warningf("[%s: %s] Task mapping not found", category, taskName)
				continue
			}

			klog.Infof("Running [%s: %s] %s %s", category, taskName, task.Script, task.Args)
			if err := runTask(task, varEnv, 10*time.Second); err != nil {
				klog.Error("Error:", err)
				failCount++
				checks := map[string][]map[string]string{
					category: {
						{
							"detection": taskName,
							"status":    "false",
						},
					},
				}
				jsonStr, err := BuildNodeReport(nodeName, varEnv["timestamp"], checks)
				if err != nil {
					klog.Error(err)
				}
				klog.Info(jsonStr)
				// TODO: post error info when detection failed
			} else {
				successCount++
			}
		}
	}

	jsonStr, err = BuildFinishFlag(nodeName)
	if err != nil {
		klog.Error(err)
	}
	klog.Info(jsonStr)
	klog.Infof("Task execution summary: total valid: %d, success: %d, failed: %d", validCount, successCount, failCount)
}
