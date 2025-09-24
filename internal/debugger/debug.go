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

	varEnv := getScriptEnv(config, detection)

	klog.Infof("At timestamp=%s, node=%s starts %d tasks", varEnv["Timestamp"], varEnv["NodeName"], validCount)
	jsonStr, err := BuildStartFlag(varEnv["NodeName"], validCount, varEnv["Timestamp"])
	if err != nil {
		klog.Error(err)
	}
	klog.Info(jsonStr)

	url := util.BuildURL(config.EisServiceAddress, config.EisServicePort, config.Register)
	resp, err := util.PostJSONString(url, jsonStr, "admin")
	klog.V(3).Info(resp)
	if err != nil {
		klog.Error(err)
		return
	}

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
			// TODO: timeout should set by config
			if exitCode, err := runTask(task, varEnv, 10*time.Second); err != nil {
				if exitCode == 100 {
					klog.Errorf("[%s: %s] post detection result failed", category, taskName)
				}
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
				jsonStr, err := BuildNodeReport(varEnv["NodeName"], varEnv["Timestamp"], checks)
				if err != nil {
					klog.Error(err)
				}
				klog.Info(jsonStr)

				url := util.BuildURL(config.EisServiceAddress, config.EisServicePort, config.Report)
				resp, err := util.PostJSONString(url, jsonStr, "admin")
				klog.V(3).Info(resp)
				if err != nil {
					klog.Error(err)
				}
			} else {
				successCount++
			}
		}
	}

	jsonStr, err = BuildFinishFlag(varEnv["NodeName"])
	if err != nil {
		klog.Error(err)
	}

	klog.Info(jsonStr)
	url = util.BuildURL(config.EisServiceAddress, config.EisServicePort, config.Terminate)
	resp, err = util.PostJSONString(url, jsonStr, "admin")
	klog.V(3).Info(resp)
	if err != nil {
		klog.Error(err)
		return
	}
	klog.Infof("Task execution summary: total valid: %d, success: %d, failed: %d", validCount, successCount, failCount)
}

// getScriptEnv returns a map containing all environment variables needed by scripts.
func getScriptEnv(config *Configuration, detection *Detection) map[string]string {
	env := make(map[string]string)

	if detection.Timestamp != "" {
		env["Timestamp"] = detection.Timestamp
	}

	if config.NodeName != "" {
		env["NodeName"] = config.NodeName
	}

	if config.LogLevel != "" {
		env["LOG_LEVEL"] = config.LogLevel
	}

	if config.LogFlag != "" {
		env["LOG_FLAG"] = config.LogFlag
	}

	if config.LogFile != "" {
		env["LOG_FILE"] = config.LogFile
	}

	if config.EisServiceAddress != "" {
		env["EIS_POST_URL"] = util.BuildURL(config.EisServiceAddress, config.EisServicePort, config.Report)
	}

	return env
}
