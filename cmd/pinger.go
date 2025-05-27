package main

import (
	_ "net/http/pprof" // #nosec
	"os"
	"strconv"

	"k8s.io/klog/v2"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/manager/signals"

	"github.com/kubecombo/kube-combo/internal/metrics"
	"github.com/kubecombo/kube-combo/internal/pinger"
)

func pingerMain() {
	defer klog.Flush()

	config, err := pinger.ParseFlags()
	if err != nil {
		LogFatalAndExit(err, "failed to parse config")
	}

	perm, err := strconv.ParseUint(config.LogPerm, 8, 32)
	if err != nil {
		LogFatalAndExit(err, "failed to parse log-perm")
	}
	InitLogFilePerm("kube-ovn-pinger", os.FileMode(perm))

	ctrl.SetLogger(klog.NewKlogr())
	ctx := signals.SetupSignalHandler()
	if config.Mode == "server" {
		if config.EnableMetrics {
			go func() {
				pinger.InitPingerMetrics()
				metrics.InitKlogMetrics()
				if err := metrics.Run(ctx, nil, JoinHostPort("0.0.0.0", config.Port), false, false); err != nil {
					LogFatalAndExit(err, "failed to run metrics server")
				}
				<-ctx.Done()
			}()
		}

		if config.EnableVerboseConnCheck {
			addr := JoinHostPort("0.0.0.0", config.UDPConnCheckPort)
			if err = UDPConnectivityListen(addr); err != nil {
				LogFatalAndExit(err, "failed to start UDP listen on addr %s", addr)
			}

			addr = JoinHostPort("0.0.0.0", config.TCPConnCheckPort)
			if err = TCPConnectivityListen(addr); err != nil {
				LogFatalAndExit(err, "failed to start TCP listen on addr %s", addr)
			}
		}
	}
	pinger.StartPinger(config, ctx.Done())
}
