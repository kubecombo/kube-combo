package debugger

import (
	_ "net/http/pprof" // #nosec
	"os"
	"strconv"

	klog "k8s.io/klog/v2"
	"sigs.k8s.io/controller-runtime/pkg/manager/signals"

	"github.com/kubecombo/kube-combo/internal/debugger"
	"github.com/kubecombo/kube-combo/internal/util"
	"github.com/kubecombo/kube-combo/versions"
)

func CmdMain() {
	klog.Info(versions.String())
	defer klog.Flush()

	config, err := debugger.ParseFlags()
	if err != nil {
		util.LogFatalAndExit(err, "failed to parse config")
	}

	perm, err := strconv.ParseUint(config.LogPerm, 8, 32)
	if err != nil {
		util.LogFatalAndExit(err, "failed to parse log-perm")
	}
	util.InitLogFilePerm("debugger", os.FileMode(perm))

	ctx := signals.SetupSignalHandler()
	debugger.StartDebugger(config, ctx.Done())
}
