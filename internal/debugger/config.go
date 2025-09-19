package debugger

import (
	"flag"
	"os"

	"github.com/kubecombo/kube-combo/internal/util"
	"github.com/spf13/pflag"
	"k8s.io/klog/v2"
)

type Configuration struct {
	TaskFile          string
	TaskFilePath      string
	ScriptFilePath    string
	LogPerm           string
	NodeName          string
	LogLevel          string
	LogFlag           string
	LogFile           string
	EisServiceAddress string
	EisServicePort    string
	Register          string
	Report            string
	Terminate         string
}

func ParseFlags() (*Configuration, error) {
	var (
		argTaskFile       = pflag.String("task", "", "File name for debugger task file")
		argTaskFilePath   = pflag.String("task-dir", util.RunAtPath, "Path to debugger task file")
		argScriptFilePath = pflag.String("script-dir", util.DetectionScriptsPath, "Path to debugger script file")
		argLogPerm        = pflag.String("log-perm", "640", "The permission for the log file")
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
		TaskFile:       *argTaskFile,
		TaskFilePath:   *argTaskFilePath,
		ScriptFilePath: *argScriptFilePath,
		LogPerm:        *argLogPerm,
		NodeName:       os.Getenv("NODE_NAME"),
		LogLevel: func() string {
			if os.Getenv("LOG_LEVEL") == "" {
				return util.LOG_LEVEL
			}
			return os.Getenv("LOG_LEVEL")
		}(),
		LogFlag: func() string {
			if os.Getenv("LOG_FLAG") == "true" {
				return "true"
			}
			return util.LOG_FLAG
		}(),
		LogFile: func() string {
			if os.Getenv("LOG_FILE") == "" {
				return util.LOG_FILE
			}
			return os.Getenv("LOG_FILE")
		}(),
		EisServiceAddress: func() string {
			if os.Getenv("EIS_API_SVC") == "" {
				return util.EIS_API_SVC
			}
			return os.Getenv("EIS_API_SVC")
		}(),
		EisServicePort: func() string {
			if os.Getenv("EIS_API_PORT") == "" {
				return util.EIS_API_PORT
			}
			return os.Getenv("EIS_API_PORT")
		}(),
		Register: func() string {
			if os.Getenv("REGISTER") == "" {
				return util.REGISTER
			}
			return os.Getenv("REGISTER")
		}(),
		Report: func() string {
			if os.Getenv("REPORT") == "" {
				return util.REPORT
			}
			return os.Getenv("REPORT")
		}(),
		Terminate: func() string {
			if os.Getenv("TERMINATE") == "" {
				return util.TERMINATE
			}
			return os.Getenv("TERMINATE")
		}(),
	}

	klog.Infof("debugger config is %+v", config)
	return config, nil
}
