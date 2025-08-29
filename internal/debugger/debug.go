package debugger

import (
	"fmt"
	"path/filepath"

	"github.com/kubecombo/kube-combo/internal/util"
	"k8s.io/klog/v2"
)

func StartDebugger(config *Configuration, stopCh <-chan struct{}) {
	if config.TaskFile == "" {
		klog.Error("TaskFile is not specified")
		return
	}

	TaskFilePath := filepath.Join(util.RunAtPath, config.TaskFile)
	if err := util.CheckFileExistence(TaskFilePath); err != nil {
		klog.Error(err)
		return
	}
	klog.Info("TaskFile exists:", TaskFilePath)

	tasks, err := loadTasks(TaskFilePath)
	if err != nil {
		klog.Error(err)
		return
	}

	for category, task := range tasks {
		fmt.Println("Category:", category)
		for _, item := range task {
			fmt.Printf("  Detection: %s, Script: %s, Args: %s\n",
				item.Detection, item.Script, item.Args)
		}
	}
}
