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
	if config.Mode == "server" {
		if config.EnableMetrics {
			go func() {
				pinger.InitPingerMetrics()
				metrics.InitKlogMetrics()
				if err := metrics.Run(ctx, nil, pinger.JoinHostPort("0.0.0.0", config.Port), false, false); err != nil {
					pinger.LogFatalAndExit(err, "failed to run metrics server")
				}
				<-ctx.Done()
			}()
		}

		if config.TCPPort != 0 {
			addr := pinger.JoinHostPort("0.0.0.0", config.TCPPort)
			if err = pinger.TCPConnectivityListen(addr); err != nil {
				pinger.LogFatalAndExit(err, "failed to start TCP listen on addr %s", addr)
			}
		}

		if config.UDPPort != 0 {
			addr := pinger.JoinHostPort("0.0.0.0", config.UDPPort)
			if err = pinger.UDPConnectivityListen(addr); err != nil {
				pinger.LogFatalAndExit(err, "failed to start UDP listen on addr %s", addr)
			}
		}
	}
	pinger.StartPinger(config, ctx.Done())
}
