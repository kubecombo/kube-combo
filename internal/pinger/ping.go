package pinger

import (
	"context"
	"errors"
	"fmt"
	"math"
	"net"
	"os"
	"slices"
	"strings"
	"time"

	goping "github.com/prometheus-community/pro-bing"
	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/klog/v2"
)

func StartPinger(config *Configuration, stopCh <-chan struct{}) {
	errHappens := false
	withMetrics := config.Mode == "server" && config.EnableMetrics
	internval := time.Duration(config.Interval) * time.Second
	timer := time.NewTimer(internval)
	timer.Stop()

LOOP:
	for {
		if ping(config, withMetrics) != nil {
			errHappens = true
		}
		if config.Mode != "server" {
			break
		}

		timer.Reset(internval)
		select {
		case <-stopCh:
			break LOOP
		case <-timer.C:
		}
	}
	timer.Stop()
	if errHappens && config.ExitCode != 0 {
		os.Exit(config.ExitCode)
	}
}

func ping(config *Configuration, withMetrics bool) error {
	errHappens := false

	if pingPods(config, withMetrics) != nil {
		errHappens = true
	}
	if pingNodes(config, withMetrics) != nil {
		errHappens = true
	}
	if dnslookup(config, withMetrics) != nil {
		errHappens = true
	}
	if config.TargetIPPorts != "" {
		if checkAccessTargetIPPorts(config) != nil {
			errHappens = true
		}
	}

	if config.ExternalAddress != "" {
		if pingExternal(config, withMetrics) != nil {
			errHappens = true
		}
	}
	if errHappens {
		return errors.New("ping failed")
	}
	return nil
}

func pingNodes(config *Configuration, setMetrics bool) error {
	klog.Infof("start to check node connectivity")
	nodes, err := config.KubeClient.CoreV1().Nodes().List(context.Background(), metav1.ListOptions{})
	if err != nil {
		klog.Errorf("failed to list nodes, %v", err)
		return err
	}

	var pingErr error
	for _, no := range nodes.Items {
		for _, addr := range no.Status.Addresses {
			if addr.Type == v1.NodeInternalIP && slices.Contains(config.PodProtocols, CheckProtocol(addr.Address)) {
				func(nodeIP, nodeName string) {
					pinger, err := goping.NewPinger(nodeIP)
					if err != nil {
						klog.Errorf("failed to init pinger, %v", err)
						pingErr = err
						return
					}
					pinger.SetPrivileged(true)
					pinger.Timeout = 30 * time.Second
					pinger.Count = 3
					pinger.Interval = 100 * time.Millisecond
					pinger.Debug = true
					if err = pinger.Run(); err != nil {
						klog.Errorf("failed to run pinger for destination %s: %v", nodeIP, err)
						pingErr = err
						return
					}

					stats := pinger.Statistics()
					klog.Infof("ping node: %s %s, count: %d, loss count %d, average rtt %.2fms",
						nodeName, nodeIP, pinger.Count, int(math.Abs(float64(stats.PacketsSent-stats.PacketsRecv))), float64(stats.AvgRtt)/float64(time.Millisecond))
					if int(math.Abs(float64(stats.PacketsSent-stats.PacketsRecv))) != 0 {
						pingErr = errors.New("ping failed")
					}
					if setMetrics {
						SetNodePingMetrics(
							config.NodeName,
							config.HostIP,
							config.PodName,
							no.Name, addr.Address,
							float64(stats.AvgRtt)/float64(time.Millisecond),
							int(math.Abs(float64(stats.PacketsSent-stats.PacketsRecv))),
							int(float64(stats.PacketsSent)))
					}
				}(addr.Address, no.Name)
			}
		}
	}
	return pingErr
}

func pingPods(config *Configuration, setMetrics bool) error {
	klog.Infof("start to check pod connectivity")
	ds, err := config.KubeClient.AppsV1().DaemonSets(config.DaemonSetNamespace).Get(context.Background(), config.DaemonSetName, metav1.GetOptions{})
	if err != nil {
		klog.Errorf("failed to get peer ds: %v", err)
		return err
	}
	pods, err := config.KubeClient.CoreV1().Pods(config.DaemonSetNamespace).List(context.Background(), metav1.ListOptions{LabelSelector: labels.Set(ds.Spec.Selector.MatchLabels).String()})
	if err != nil {
		klog.Errorf("failed to list peer pods: %v", err)
		return err
	}

	var pingErr error
	for _, pod := range pods.Items {
		for _, podIP := range pod.Status.PodIPs {
			if slices.Contains(config.PodProtocols, CheckProtocol(podIP.IP)) {
				func(podIP, podName, nodeIP, nodeName string) {
					if config.TCPPort != 0 {
						if err := TCPConnectivityCheck(JoinHostPort(podIP, config.TCPPort)); err != nil {
							klog.Infof("TCP connectivity to pod %s %s failed", podName, podIP)
							pingErr = err
						} else {
							klog.Infof("TCP connectivity to pod %s %s success", podName, podIP)
						}
					}
					if config.UDPPort != 0 {
						if err := UDPConnectivityCheck(JoinHostPort(podIP, config.UDPPort)); err != nil {
							klog.Infof("UDP connectivity to pod %s %s failed", podName, podIP)
							pingErr = err
						} else {
							klog.Infof("UDP connectivity to pod %s %s success", podName, podIP)
						}
					}

					pinger, err := goping.NewPinger(podIP)
					if err != nil {
						klog.Errorf("failed to init pinger, %v", err)
						pingErr = err
						return
					}
					pinger.SetPrivileged(true)
					pinger.Timeout = 1 * time.Second
					pinger.Debug = true
					pinger.Count = 3
					pinger.Interval = 100 * time.Millisecond
					if err = pinger.Run(); err != nil {
						klog.Errorf("failed to run pinger for destination %s: %v", podIP, err)
						pingErr = err
						return
					}

					stats := pinger.Statistics()
					klog.Infof("ping pod: %s %s, count: %d, loss count %d, average rtt %.2fms",
						podName, podIP, pinger.Count, int(math.Abs(float64(stats.PacketsSent-stats.PacketsRecv))), float64(stats.AvgRtt)/float64(time.Millisecond))
					if int(math.Abs(float64(stats.PacketsSent-stats.PacketsRecv))) != 0 {
						pingErr = errors.New("ping failed")
					}
					if setMetrics {
						SetPodPingMetrics(
							config.NodeName,
							config.HostIP,
							config.PodName,
							nodeName,
							nodeIP,
							podIP,
							float64(stats.AvgRtt)/float64(time.Millisecond),
							int(math.Abs(float64(stats.PacketsSent-stats.PacketsRecv))),
							int(float64(stats.PacketsSent)))
					}
				}(podIP.IP, pod.Name, pod.Status.HostIP, pod.Spec.NodeName)
			}
		}
	}
	return pingErr
}

func pingExternal(config *Configuration, setMetrics bool) error {
	if config.ExternalAddress == "" {
		return nil
	}

	addresses := strings.SplitSeq(config.ExternalAddress, ",")
	for addr := range addresses {
		if !slices.Contains(config.PodProtocols, CheckProtocol(addr)) {
			continue
		}

		klog.Infof("start to check ping external to %s", addr)
		pinger, err := goping.NewPinger(addr)
		if err != nil {
			klog.Errorf("failed to init pinger, %v", err)
			return err
		}
		pinger.SetPrivileged(true)
		pinger.Timeout = 5 * time.Second
		pinger.Debug = true
		pinger.Count = 3
		pinger.Interval = 100 * time.Millisecond
		if err = pinger.Run(); err != nil {
			klog.Errorf("failed to run pinger for destination %s: %v", addr, err)
			return err
		}
		stats := pinger.Statistics()
		klog.Infof("ping external address: %s, total count: %d, loss count %d, average rtt %.2fms",
			addr, pinger.Count, int(math.Abs(float64(stats.PacketsSent-stats.PacketsRecv))), float64(stats.AvgRtt)/float64(time.Millisecond))
		if setMetrics {
			SetExternalPingMetrics(
				config.NodeName,
				config.HostIP,
				config.PodIP,
				addr,
				float64(stats.AvgRtt)/float64(time.Millisecond),
				int(math.Abs(float64(stats.PacketsSent-stats.PacketsRecv))))
		}
		if int(math.Abs(float64(stats.PacketsSent-stats.PacketsRecv))) != 0 {
			return errors.New("ping failed")
		}
	}

	return nil
}

func checkAccessTargetIPPorts(config *Configuration) error {
	klog.Infof("start to check Service or externalIPPort connectivity")
	if config.TargetIPPorts == "" {
		return nil
	}
	var checkErr error
	targetIPPorts := strings.SplitSeq(config.TargetIPPorts, ",")
	for targetIPPort := range targetIPPorts {
		klog.Infof("checking targetIPPort %s", targetIPPort)
		items := strings.Split(targetIPPort, "-")
		if len(items) != 3 {
			klog.Infof("targetIPPort format failed")
			continue
		}
		proto := items[0]
		addr := items[1]
		port := items[2]

		if !slices.Contains(config.PodProtocols, CheckProtocol(addr)) {
			continue
		}
		if CheckProtocol(addr) == ProtocolIPv6 {
			addr = fmt.Sprintf("[%s]", addr)
		}

		switch proto {
		case ProtocolTCP:
			if err := TCPConnectivityCheck(fmt.Sprintf("%s:%s", addr, port)); err != nil {
				klog.Infof("TCP connectivity to targetIPPort %s:%s failed", addr, port)
				checkErr = err
			} else {
				klog.Infof("TCP connectivity to targetIPPort %s:%s success", addr, port)
			}
		case ProtocolUDP:
			if err := UDPConnectivityCheck(fmt.Sprintf("%s:%s", addr, port)); err != nil {
				klog.Infof("UDP connectivity to target %s:%s failed", addr, port)
				checkErr = err
			} else {
				klog.Infof("UDP connectivity to target %s:%s success", addr, port)
			}
		default:
			klog.Infof("unrecognized protocol %s", proto)
			continue
		}
	}
	return checkErr
}

func dnslookup(config *Configuration, setMetrics bool) error {
	klog.Infof("start to check dns connectivity")
	t1 := time.Now()
	ctx, cancel := context.WithTimeout(context.TODO(), 10*time.Second)
	defer cancel()
	var r net.Resolver
	addrs, err := r.LookupHost(ctx, config.ExternalDNS)
	elapsed := time.Since(t1)
	if err != nil {
		klog.Errorf("failed to resolve dns %s, %v", config.ExternalDNS, err)
		if setMetrics {
			SetDnsUnhealthyMetrics(config.NodeName)
		}
		return err
	}
	if setMetrics {
		SetDnsHealthyMetrics(config.NodeName, float64(elapsed)/float64(time.Millisecond))
	}
	klog.Infof("resolve dns %s to %v in %.2fms", config.ExternalDNS, addrs, float64(elapsed)/float64(time.Millisecond))
	return nil
}
