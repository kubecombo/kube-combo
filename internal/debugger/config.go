package debugger

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/kubecombo/kube-combo/internal/util"
	"github.com/spf13/pflag"
	"k8s.io/klog/v2"
)

type Task struct {
	Detection string `json:"detection"`
	Script    string `json:"script"`
	Args      string `json:"args"`
}

type Configuration struct {
	TaskFile string
	LogPerm  string
}

func ParseFlags() (*Configuration, error) {
	var (
		argTaskFile = pflag.String("task", "", "Path to debugger task file")
		argLogPerm  = pflag.String("log-perm", "640", "The permission for the log file")
	)

	klogFlags := flag.NewFlagSet("klog", flag.ExitOnError)
	klog.InitFlags(klogFlags)

	// Sync the glog and klog flags.
	pflag.CommandLine.VisitAll(func(f1 *pflag.Flag) {
		f2 := klogFlags.Lookup(f1.Name)
		if f2 != nil {
			value := f1.Value.String()
			if err := f2.Value.Set(value); err != nil {
				util.LogFatalAndExit(err, "failed to set flag")
			}
		}
	})

	pflag.CommandLine.AddGoFlagSet(klogFlags)
	pflag.CommandLine.AddGoFlagSet(flag.CommandLine)
	pflag.Parse()

	config := &Configuration{
		TaskFile: *argTaskFile,
		LogPerm:  *argLogPerm,
	}

	klog.Infof("debugger config is %+v", config)
	return config, nil
}

func loadTasks(filePath string) (map[string][]Task, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open file: %v", err)
	}
	defer f.Close()

	var tasks map[string][]Task
	decoder := json.NewDecoder(f)
	if err := decoder.Decode(&tasks); err != nil {
		return nil, fmt.Errorf("failed to decode json: %v", err)
	}

	return tasks, nil
}
