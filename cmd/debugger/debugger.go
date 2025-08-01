package debugger

import (
	_ "net/http/pprof" // #nosec

	klog "k8s.io/klog/v2"
	ctrl "sigs.k8s.io/controller-runtime"

	"github.com/kubecombo/kube-combo/versions"
)

func CmdMain() {
	klog.Info(versions.String())

	defer klog.Flush()

	ctrl.SetLogger(klog.NewKlogr())

}
