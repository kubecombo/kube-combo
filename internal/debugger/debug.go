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
				// TODO: post error info when detection failed
			} else {
				successCount++
			}
		}
	}
	klog.Infof("Task execution summary: total valid: %d, success: %d, failed: %d", validCount, successCount, failCount)
}
