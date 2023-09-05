package controller

import "github.com/prometheus/client_golang/prometheus"

var (
	updates = prometheus.NewCounter(prometheus.CounterOpts{
		Namespace: "default",
		Subsystem: "kube_combo",
		Name:      "updates_total",
		Help:      "Number of k8s object updates that have been processed.",
	})

	updateErrors = prometheus.NewCounter(prometheus.CounterOpts{
		Namespace: "default",
		Subsystem: "kube_combo",
		Name:      "update_errors_total",
		Help:      "Number of k8s object updates that failed for some reason.",
	})

	configLoaded = prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: "default",
		Subsystem: "kube_combo",
		Name:      "config_loaded_bool",
		Help:      "1 if the kube-combo configuration was successfully loaded at least once.",
	})

	configStale = prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: "default",
		Subsystem: "kube_combo",
		Name:      "config_stale_bool",
		Help:      "1 if running on a stale configuration, because the latest config failed to load.",
	})
)

func init() {
	prometheus.MustRegister(updates)
	prometheus.MustRegister(updateErrors)
	prometheus.MustRegister(configLoaded)
	prometheus.MustRegister(configStale)
}
