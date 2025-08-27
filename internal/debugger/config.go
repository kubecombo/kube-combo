package debugger

import (
	"flag"
	"os"

	"github.com/kubecombo/kube-combo/internal/util"
	"github.com/spf13/pflag"
	"k8s.io/client-go/kubernetes"
	"k8s.io/klog/v2"
)

type Configuration struct {
	KubeConfigFile     string
	KubeClient         kubernetes.Interface
	DaemonSetNamespace string
	DaemonSetName      string
	Interval           int
	Mode               string
	ExitCode           int
	NodeName           string
	HostIP             string
	PodName            string
	PodIP              string
	PodProtocols       []string
	EnableMetrics      bool
	Port               int32
	LogPerm            string

	// ArpPing   string // TODO
	Ping      string
	TCPPing   string
	UDPPing   string
	DnsLookup string

	// enable Node ip check
	EnableNodeIPCheck bool
}

func ParseFlags() (*Configuration, error) {
	var (
		argPort               = pflag.Int32("port", 8080, "metrics port")
		argKubeConfigFile     = pflag.String("kubeconfig", "", "Path to kubeconfig file with authorization and master location information. If not set use the inCluster token.")
		argDaemonSetNameSpace = pflag.String("ds-namespace", "kube-system", "kube-ovn-pinger daemonset namespace")
		argDaemonSetName      = pflag.String("ds-name", "kube-ovn-pinger", "kube-ovn-pinger daemonset name")
		argInterval           = pflag.Int("interval", 5, "interval seconds between consecutive pings")
		argMode               = pflag.String("mode", "server", "server or job Mode")
		argEnableMetrics      = pflag.Bool("enable-metrics", false, "Whether to support metrics query")
		argLogPerm            = pflag.String("log-perm", "640", "The permission for the log file")
		argExitCode           = pflag.Int("exit-code", 1, "exit code when failure happens")
		argPing               = pflag.String("ping", "", "check ping connection to an external address, eg: '1.1.1.1,2.2.2.2'")
		argTCPPing            = pflag.String("tcpping", "", "target tcp ip and port, eg: '10.16.0.9:80,10.16.0.10:80'")
		argUDPPing            = pflag.String("udpping", "", "target udp ip and port, eg: '10.16.0.9:53,10.16.0.10:53'")
		argDnsLookup          = pflag.String("dnslookup", "", "check external dns resolve from pod, eg: 'baidu.com,google.com'")
		argEnableNodeIPCheck  = pflag.Bool("enable-node-ip-check", false, "Whether to enable node IP check")
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
		KubeConfigFile:     *argKubeConfigFile,
		KubeClient:         nil,
		Port:               *argPort,
		DaemonSetNamespace: *argDaemonSetNameSpace,
		DaemonSetName:      *argDaemonSetName,
		Interval:           *argInterval,
		Mode:               *argMode,
		ExitCode:           *argExitCode,
		PodIP:              os.Getenv("POD_IP"),
		HostIP:             os.Getenv("HOST_IP"),
		NodeName:           os.Getenv("NODE_NAME"),
		PodName:            os.Getenv("POD_NAME"),
		EnableMetrics:      *argEnableMetrics,

		Ping:      *argPing,
		TCPPing:   *argTCPPing,
		UDPPing:   *argUDPPing,
		DnsLookup: *argDnsLookup,

		EnableNodeIPCheck: *argEnableNodeIPCheck,

		LogPerm: *argLogPerm,
	}

	klog.Infof("debugger config is %+v", config)
	return config, nil
}
