package pinger

import (
	"context"
	"flag"
	"os"
	"time"

	"github.com/spf13/pflag"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
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
	TCPPort            int32
	UDPPort            int32
	LogPerm            string

	// ArpPing   string // TODO
	Ping      string
	TCPPing   string
	UDPPing   string
	DnsLookup string
}

func ParseFlags() (*Configuration, error) {
	var (
		argPort = pflag.Int32("port", 8080, "metrics port")

		argTCPPort = pflag.Int32("tcp-port", 54321, "TCP connectivity auto check pod ip tcp port")
		argUDPPort = pflag.Int32("udp-port", 54322, "UDP connectivity auto check pod ip udp port")

		argKubeConfigFile     = pflag.String("kubeconfig", "", "Path to kubeconfig file with authorization and master location information. If not set use the inCluster token.")
		argDaemonSetNameSpace = pflag.String("ds-namespace", "kube-system", "kube-ovn-pinger daemonset namespace")
		argDaemonSetName      = pflag.String("ds-name", "kube-ovn-pinger", "kube-ovn-pinger daemonset name")
		argInterval           = pflag.Int("interval", 5, "interval seconds between consecutive pings")
		argMode               = pflag.String("mode", "server", "server or job Mode")
		argEnableMetrics      = pflag.Bool("enable-metrics", true, "Whether to support metrics query")
		argLogPerm            = pflag.String("log-perm", "640", "The permission for the log file")
		argExitCode           = pflag.Int("exit-code", -1, "exit code when failure happens")
		argPing               = pflag.String("ping", "", "check ping connection to an external address, eg: '1.1.1.1,2.2.2.2'")
		argTCPPing            = pflag.String("tcpping", "", "target tcp ip and port, eg: '10.16.0.9:80,10.16.0.10:80'")
		argUDPPing            = pflag.String("udpping", "", "target udp ip and port, eg: '10.16.0.9:53,10.16.0.10:53'")
		argDnsLookup          = pflag.String("dnslookup", "", "check external dns resolve from pod, eg: 'baidu.com,google.com'")
	)
	klogFlags := flag.NewFlagSet("klog", flag.ExitOnError)
	klog.InitFlags(klogFlags)

	// Sync the glog and klog flags.
	pflag.CommandLine.VisitAll(func(f1 *pflag.Flag) {
		f2 := klogFlags.Lookup(f1.Name)
		if f2 != nil {
			value := f1.Value.String()
			if err := f2.Value.Set(value); err != nil {
				LogFatalAndExit(err, "failed to set flag")
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

		TCPPort: *argTCPPort,
		UDPPort: *argUDPPort,

		Ping:      *argPing,
		TCPPing:   *argTCPPing,
		UDPPing:   *argUDPPing,
		DnsLookup: *argDnsLookup,

		LogPerm: *argLogPerm,
	}
	if err := config.initKubeClient(); err != nil {
		return nil, err
	}

	podName := os.Getenv("POD_NAME")
	for range 3 {
		pod, err := config.KubeClient.CoreV1().Pods(config.DaemonSetNamespace).Get(context.Background(), podName, metav1.GetOptions{})
		if err != nil {
			klog.Errorf("failed to get self pod %s/%s: %v", config.DaemonSetNamespace, podName, err)
			return nil, err
		}

		if len(pod.Status.PodIPs) != 0 {
			config.PodProtocols = make([]string, len(pod.Status.PodIPs))
			for i, podIP := range pod.Status.PodIPs {
				config.PodProtocols[i] = CheckProtocol(podIP.IP)
			}
			break
		}

		if len(pod.Status.ContainerStatuses) != 0 && pod.Status.ContainerStatuses[0].Ready {
			LogFatalAndExit(nil, "failed to get IPs of Pod %s/%s: podIPs is empty while the container is ready", config.DaemonSetNamespace, podName)
		}

		klog.Errorf("cannot get Pod IPs now, waiting Pod to be ready")
		time.Sleep(time.Second)
	}

	if len(config.PodProtocols) == 0 {
		LogFatalAndExit(nil, "failed to get IPs of Pod %s/%s after 3 attempts", config.DaemonSetNamespace, podName)
	}

	klog.Infof("pinger config is %+v", config)
	return config, nil
}

func (config *Configuration) initKubeClient() error {
	var cfg *rest.Config
	var err error
	if config.KubeConfigFile == "" {
		cfg, err = rest.InClusterConfig()
		if err != nil {
			klog.Errorf("use in cluster config failed %v", err)
			return err
		}
	} else {
		cfg, err = clientcmd.BuildConfigFromFlags("", config.KubeConfigFile)
		if err != nil {
			klog.Errorf("use --kubeconfig %s failed %v", config.KubeConfigFile, err)
			return err
		}
	}
	cfg.Timeout = 15 * time.Second
	cfg.QPS = 1000
	cfg.Burst = 2000
	cfg.ContentType = "application/vnd.kubernetes.protobuf"
	cfg.AcceptContentTypes = "application/vnd.kubernetes.protobuf,application/json"
	kubeClient, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		klog.Errorf("init kubernetes client failed %v", err)
		return err
	}
	config.KubeClient = kubeClient
	return nil
}
