package debugger

import (
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

	if config.NodeName == "" {
		klog.Error("NODE_NAME not set")
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
	validCount := CountValidTasks(detection.Tasks)
	if validCount == 0 {
		klog.Warning("No valid tasks found")
		return
	}

	// TODO: function to get all scripts env
	varEnv := map[string]string{}
	if detection.Timestamp != "" {
		varEnv["timestamp"] = detection.Timestamp
	}

	klog.Infof("At timestamp=%s, node=%s starts %d tasks", detection.Timestamp, config.NodeName, validCount)
	jsonStr, err := BuildStartFlag(config.NodeName, validCount, varEnv["timestamp"])
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
				jsonStr, err := BuildNodeReport(config.NodeName, varEnv["timestamp"], checks)
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

	jsonStr, err = BuildFinishFlag(config.NodeName)
	if err != nil {
		klog.Error(err)
	}

	// TODO post finish flag at finish time
	klog.Info(jsonStr)
	klog.Infof("Task execution summary: total valid: %d, success: %d, failed: %d", validCount, successCount, failCount)
}
