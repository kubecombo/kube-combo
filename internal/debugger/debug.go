package debugger

import (
	"path/filepath"

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

	metrics, err := loadMetrics(taskFilePath)
	if err != nil {
		klog.Error(err)
		return
	}

	varEnv := map[string]string{}
	if metrics.Timestamp != "" {
		varEnv["timestamp"] = metrics.Timestamp
	}

	for category, taskNames := range metrics.Tasks {
		for _, taskName := range taskNames {
			task, ok := TaskMap[taskName]
			if !ok {
				klog.Warningf("[%s: %s] Task mapping not found\n", category, taskName)
				continue
			}

			klog.Infof("Running [%s: %s] %s %s\n", category, taskName, task.Script, task.Args)
			if err := runTask(task, varEnv); err != nil {
				klog.Error("Error:", err)
				// TODO: post error info when detection failed
			}
		}
	}
}
