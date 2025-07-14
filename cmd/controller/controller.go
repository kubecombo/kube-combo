/*
Copyright 2023 kubecombo.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controller

import (
	"flag"
	"os"

	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/kubernetes"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	_ "k8s.io/client-go/plugin/pkg/client/auth"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"

	myv1 "github.com/kubecombo/kube-combo/api/v1"
	"github.com/kubecombo/kube-combo/internal/controller"
	"github.com/kubecombo/kube-combo/versions"
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))

	utilruntime.Must(myv1.AddToScheme(scheme))
	//+kubebuilder:scaffold:scheme
}

func CmdMain() {
	var metricsAddr string
	var enableLeaderElection bool
	var probeAddr string
	var enableWebhooks bool
	var k8sManifestsPath string
	var sslVpnSecretPath, dhSecretPath string
	var sslVpnTCP, sslVpnUDP string
	var ipSecBootPcPort, ipSecIsakmpPort, ipSecNatPort, ipSecVpnSecretPath string
	flag.BoolVar(&enableWebhooks, "enable-webhooks", os.Getenv("ENABLE_WEBHOOKS") == "true", "Enable webhooks")
	flag.StringVar(&metricsAddr, "metrics-bind-address", "127.0.0.1", "The address the metric endpoint binds to.")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":38081", "The address the probe endpoint binds to.")
	// vpn gw server pod need those config to start
	flag.StringVar(&k8sManifestsPath, "k8s-manifests-path", "/etc/kubernetes/manifests", "The path the ssl vpn daemonset pod will copy static pod yaml to.")
	// ssl vpn
	flag.StringVar(&sslVpnSecretPath, "ssl-vpn-secret-path", "/etc/openvpn/certmanager", "The path the ssl vpn pod will copy secrets to.")
	flag.StringVar(&dhSecretPath, "dh-secret-path", "/etc/openvpn/dh", "The path the ssl vpn pod will copy dh secrets to.")
	flag.StringVar(&ipSecVpnSecretPath, "ip-sec-vpn-secret-path", "/etc/ipsec/certs", "The path the ip sec vpn pod will copy to.")
	flag.StringVar(&sslVpnTCP, "ssl-vpn-tcp-port", "443", "The port the ssl vpn server binds to.")
	flag.StringVar(&sslVpnUDP, "ssl-vpn-udp-port", "1194", "The port the ssl vpn server binds to.")
	// ipsec vpn
	flag.StringVar(&ipSecBootPcPort, "ip-sec-boot-pc-port", "68", "The port the ip sec vpn server binds to.")
	flag.StringVar(&ipSecIsakmpPort, "ip-sec-isakmp-pc-port", "500", "The port the ip sec vpn server binds to.")
	flag.StringVar(&ipSecNatPort, "ip-sec-nat-port", "4500", "The port the ip sec vpn server binds to.")

	flag.BoolVar(&enableLeaderElection, "leader-elect", false,
		"Enable leader election for controller manager. "+
			"Enabling this will ensure there is only one active controller manager.")
	opts := zap.Options{
		Development: true,
	}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))
	// source code version
	setupLog.Info(versions.String())
	restConfig := ctrl.GetConfigOrDie()
	kubeClient, err := kubernetes.NewForConfig(restConfig)
	if err != nil {
		setupLog.Error(err, "unable to get kubeClient")
		os.Exit(1)
	}

	bindAddress := metricsAddr + ":9443"
	metricsOptions := metricsserver.Options{
		BindAddress: bindAddress,
	}

	// TODO:// fix ctrl.GetConfigOrDie() called multiple times
	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		Metrics:                metricsOptions,
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "8e41f5a6.kubecombo.com",
		// LeaderElectionReleaseOnCancel defines if the leader should step down voluntarily
		// when the Manager ends. This requires the binary to immediately end when the
		// Manager is stopped, otherwise, this setting is unsafe. Setting this significantly
		// speeds up voluntary leader transitions as the new leader don't have to wait
		// LeaseDuration time first.
		//
		// In the default scaffold provided, the program ends immediately after
		// the manager stops, so would be fine to enable this option. However,
		// if you are doing or is intended to do any operation such as perform cleanups
		// after the manager stops then its usage might be unsafe.
		// LeaderElectionReleaseOnCancel: true,
	})
	if err != nil {
		setupLog.Error(err, "unable to start manager")
		os.Exit(1)
	}

	// vpn gw controllers
	if err = (&controller.VpnGwReconciler{
		Client:     mgr.GetClient(),
		KubeClient: kubeClient,
		Scheme:     mgr.GetScheme(),
		RestConfig: restConfig,
		Log:        ctrl.Log.WithName("vpngw"),
		// vpn gw
		SslVpnTCP:          sslVpnTCP,
		SslVpnUDP:          sslVpnUDP,
		IPSecBootPcPort:    ipSecBootPcPort,
		IPSecIsakmpPort:    ipSecIsakmpPort,
		IPSecNatPort:       ipSecNatPort,
		SslVpnSecretPath:   sslVpnSecretPath,
		DhSecretPath:       dhSecretPath,
		K8sManifestsPath:   k8sManifestsPath,
		IPSecVpnSecretPath: ipSecVpnSecretPath,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "VpnGw")
		os.Exit(1)
	}
	if err = (&controller.IpsecConnReconciler{
		Client: mgr.GetClient(),
		Scheme: mgr.GetScheme(),
		Log:    ctrl.Log.WithName("ipsecconn"),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "IpsecConn")
		os.Exit(1)
	}
	if err = (&controller.KeepAlivedReconciler{
		Client: mgr.GetClient(),
		Scheme: mgr.GetScheme(),
		Log:    ctrl.Log.WithName("keepalived"),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "KeepAlived")
		os.Exit(1)
	}

	// debugger controllers
	if err = (&controller.DebuggerReconciler{
		Client:     mgr.GetClient(),
		KubeClient: kubeClient,
		Scheme:     mgr.GetScheme(),
		RestConfig: restConfig,
		Log:        ctrl.Log.WithName("debugger"),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "Debugger")
		os.Exit(1)
	}
	if err = (&controller.PingerReconciler{
		Client: mgr.GetClient(),
		Scheme: mgr.GetScheme(),
		Log:    ctrl.Log.WithName("pinger"),
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "Pinger")
		os.Exit(1)
	}

	if enableWebhooks {
		setupLog.Info("enabling webhooks")
		if err = (&myv1.VpnGw{}).SetupWebhookWithManager(mgr); err != nil {
			setupLog.Error(err, "unable to create webhook", "webhook", "VpnGw")
			os.Exit(1)
		}

		if err = (&myv1.IpsecConn{}).SetupWebhookWithManager(mgr); err != nil {
			setupLog.Error(err, "unable to create webhook", "webhook", "IpsecConn")
			os.Exit(1)
		}

		if err = (&myv1.KeepAlived{}).SetupWebhookWithManager(mgr); err != nil {
			setupLog.Error(err, "unable to create webhook", "webhook", "KeepAlived")
			os.Exit(1)
		}
		if err = (&myv1.Debugger{}).SetupWebhookWithManager(mgr); err != nil {
			setupLog.Error(err, "unable to create webhook", "webhook", "Debugger")
			os.Exit(1)
		}
		if err = (&myv1.Pinger{}).SetupWebhookWithManager(mgr); err != nil {
			setupLog.Error(err, "unable to create webhook", "webhook", "Pinger")
			os.Exit(1)
		}
	} else {
		setupLog.Info("webhooks disabled")
	}

	//+kubebuilder:scaffold:builder
	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "unable to set up health check")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "unable to set up ready check")
		os.Exit(1)
	}

	setupLog.Info("starting manager")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "problem running manager")
		os.Exit(1)
	}
}
