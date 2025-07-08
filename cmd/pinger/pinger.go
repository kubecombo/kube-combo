package pinger

import (
	_ "net/http/pprof" // #nosec
	"os"
	"strconv"

	klog "k8s.io/klog/v2"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/manager/signals"

	"github.com/kubecombo/kube-combo/internal/metrics"
	"github.com/kubecombo/kube-combo/internal/pinger"
)

func CmdMain() {
	defer klog.Flush()

	config, err := pinger.ParseFlags()
	if err != nil {
		pinger.LogFatalAndExit(err, "failed to parse config")
	}

	perm, err := strconv.ParseUint(config.LogPerm, 8, 32)
	if err != nil {
		pinger.LogFatalAndExit(err, "failed to parse log-perm")
	}
	pinger.InitLogFilePerm("pinger", os.FileMode(perm))

	ctrl.SetLogger(klog.NewKlogr())
	ctx := signals.SetupSignalHandler()
	if config.Mode == "server" && config.EnableMetrics {
		go func() {
			pinger.InitPingerMetrics()
			metrics.InitKlogMetrics()
			klog.V(3).Info("start metrics server")
			if err := metrics.Run(ctx, nil, pinger.JoinHostPort("0.0.0.0", config.Port), false, false); err != nil {
				klog.Error(err, "failed to run metrics server")
				pinger.LogFatalAndExit(err, "failed to run metrics server")
			}
			<-ctx.Done()
			klog.V(3).Info("stop metrics server")
		}()
	}
	pinger.StartPinger(config, ctx.Done())
}
