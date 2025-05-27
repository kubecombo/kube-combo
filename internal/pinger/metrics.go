package pinger

import (
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

var (
	dnsHealthyGauge = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "pinger_dns_healthy",
			Help: "If the dns request is healthy on this node",
		},
		[]string{
			"nodeName",
		})
	dnsUnhealthyGauge = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "pinger_dns_unhealthy",
			Help: "If the dns request is unhealthy on this node",
		},
		[]string{
			"nodeName",
		})
	dnsRequestLatencyHistogram = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "pinger_dns_latency_ms",
			Help:    "The latency ms histogram the node request internal dns",
			Buckets: []float64{2, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50},
		},
		[]string{
			"nodeName",
		})
	podPingLatencyHistogram = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "pinger_pod_ping_latency_ms",
			Help:    "The latency ms histogram for pod peer ping",
			Buckets: []float64{.25, .5, 1, 2, 5, 10, 30},
		},
		[]string{
			"src_node_name",
			"src_node_ip",
			"src_pod_ip",
			"target_node_name",
			"target_node_ip",
			"target_pod_ip",
		})
	podPingLostCounter = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "pinger_pod_ping_lost_total",
			Help: "The lost count for pod peer ping",
		}, []string{
			"src_node_name",
			"src_node_ip",
			"src_pod_ip",
			"target_node_name",
			"target_node_ip",
			"target_pod_ip",
		})
	podPingTotalCounter = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "pinger_pod_ping_count_total",
			Help: "The total count for pod peer ping",
		}, []string{
			"src_node_name",
			"src_node_ip",
			"src_pod_ip",
			"target_node_name",
			"target_node_ip",
			"target_pod_ip",
		})
	nodePingLatencyHistogram = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "pinger_node_ping_latency_ms",
			Help:    "The latency ms histogram for pod ping node",
			Buckets: []float64{.25, .5, 1, 2, 5, 10, 30},
		},
		[]string{
			"src_node_name",
			"src_node_ip",
			"src_pod_ip",
			"target_node_name",
			"target_node_ip",
		})
	nodePingLostCounter = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "pinger_node_ping_lost_total",
			Help: "The lost count for pod ping node",
		}, []string{
			"src_node_name",
			"src_node_ip",
			"src_pod_ip",
			"target_node_name",
			"target_node_ip",
		})
	nodePingTotalCounter = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "pinger_node_ping_count_total",
			Help: "The total count for pod ping node",
		}, []string{
			"src_node_name",
			"src_node_ip",
			"src_pod_ip",
			"target_node_name",
			"target_node_ip",
		})
	externalPingLatencyHistogram = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "pinger_external_ping_latency_ms",
			Help:    "The latency ms histogram for pod ping external address",
			Buckets: []float64{.25, .5, 1, 2, 5, 10, 30, 50, 100},
		},
		[]string{
			"src_node_name",
			"src_node_ip",
			"src_pod_ip",
			"target_address",
		})
	externalPingLostCounter = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "pinger_external_ping_lost_total",
			Help: "The lost count for pod ping external address",
		}, []string{
			"src_node_name",
			"src_node_ip",
			"src_pod_ip",
			"target_address",
		})
)

func InitPingerMetrics() {
	metrics.Registry.MustRegister(dnsHealthyGauge)
	metrics.Registry.MustRegister(dnsUnhealthyGauge)
	metrics.Registry.MustRegister(dnsRequestLatencyHistogram)
	metrics.Registry.MustRegister(podPingLatencyHistogram)
	metrics.Registry.MustRegister(podPingLostCounter)
	metrics.Registry.MustRegister(podPingTotalCounter)
	metrics.Registry.MustRegister(nodePingLatencyHistogram)
	metrics.Registry.MustRegister(nodePingLostCounter)
	metrics.Registry.MustRegister(nodePingTotalCounter)
	metrics.Registry.MustRegister(externalPingLatencyHistogram)
	metrics.Registry.MustRegister(externalPingLostCounter)
}

func SetPodPingMetrics(srcNodeName, srcNodeIP, srcPodIP, targetNodeName, targetNodeIP, targetPodIP string, latency float64, lost, total int) {
	podPingLatencyHistogram.WithLabelValues(
		srcNodeName,
		srcNodeIP,
		srcPodIP,
		targetNodeName,
		targetNodeIP,
		targetPodIP,
	).Observe(latency)
	podPingLostCounter.WithLabelValues(
		srcNodeName,
		srcNodeIP,
		srcPodIP,
		targetNodeName,
		targetNodeIP,
		targetPodIP,
	).Add(float64(lost))
	podPingTotalCounter.WithLabelValues(
		srcNodeName,
		srcNodeIP,
		srcPodIP,
		targetNodeName,
		targetNodeIP,
		targetPodIP,
	).Add(float64(total))
}

func SetNodePingMetrics(srcNodeName, srcNodeIP, srcPodIP, targetNodeName, targetNodeIP string, latency float64, lost, total int) {
	nodePingLatencyHistogram.WithLabelValues(
		srcNodeName,
		srcNodeIP,
		srcPodIP,
		targetNodeName,
		targetNodeIP,
	).Observe(latency)
	nodePingLostCounter.WithLabelValues(
		srcNodeName,
		srcNodeIP,
		srcPodIP,
		targetNodeName,
		targetNodeIP,
	).Add(float64(lost))
	nodePingTotalCounter.WithLabelValues(
		srcNodeName,
		srcNodeIP,
		srcPodIP,
		targetNodeName,
		targetNodeIP,
	).Add(float64(total))
}

func SetExternalPingMetrics(srcNodeName, srcNodeIP, srcPodIP, targetAddress string, latency float64, lost int) {
	externalPingLatencyHistogram.WithLabelValues(
		srcNodeName,
		srcNodeIP,
		srcPodIP,
		targetAddress,
	).Observe(latency)
	externalPingLostCounter.WithLabelValues(
		srcNodeName,
		srcNodeIP,
		srcPodIP,
		targetAddress,
	).Add(float64(lost))
}

func SetDnsHealthyMetrics(nodeName string, latency float64) {
	dnsHealthyGauge.WithLabelValues(nodeName).Set(1)
	dnsRequestLatencyHistogram.WithLabelValues(nodeName).Observe(latency)
	dnsUnhealthyGauge.WithLabelValues(nodeName).Set(0)
}

func SetDnsUnhealthyMetrics(nodeName string) {
	dnsHealthyGauge.WithLabelValues(nodeName).Set(0)
	dnsUnhealthyGauge.WithLabelValues(nodeName).Set(1)
}
