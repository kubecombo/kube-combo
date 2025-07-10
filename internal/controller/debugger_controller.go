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
	"context"
	"errors"
	"fmt"
	"reflect"
	"strconv"
	"strings"
	"time"

	"github.com/go-logr/logr"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	myv1 "github.com/kubecombo/kube-combo/api/v1"
)

const (
	DebuggerName = "debug"
	PingerName   = "ping"

	ScriptsPath = "scripts"

	DebuggerStartCMD = "/debugger-start.sh"
	PingerStartCMD   = "/pinger-start.sh"

	// WorkloadTypePod is the workload type for pod
	WorkloadTypePod = "pod"
	// WorkloadTypeDaemonset is the workload type for daemonset
	WorkloadTypeDaemonset = "daemonset"
	// debugger env
	Subnet = "SUBNET"
	// pinger env
	Ping    = "PING"
	TcpPing = "TCP_PING"
	UdpPing = "UDP_PING"
	Dns     = "DNS"

	EnableMetrics = "ENABLE_METRICS"

	// service account
	ServiceAccountName = "kube-ovn-app"
)

// volume mounts
const (
	// volume path and name
	VarRunOpenvswitch = "/var/run/openvswitch"
	OpenvswitchName   = "host-run-ovs"

	VarRunOvn = "/var/run/ovn"
	OvnName   = "host-run-ovn"

	EtcOpenvswitch    = "/etc/openvswitch"
	OpenvswitchConfig = "host-config-openvswitch"

	VarLogOpenvswitch = "/var/log/openvswitch"
	OpenvswitchLog    = "host-log-openvswitch"

	VarLogOvn = "/var/log/ovn"
	OvnLog    = "host-log-ovn"

	VarLogKubeOvn = "/var/log/kube-ovn"
	KubeOvnLog    = "host-log-kube-ovn"

	VarLogKubeCombo = "/var/log/kube-combo"
	KubeComboLog    = "host-log-kube-combo"

	EtcLocalTime  = "/etc/localtime"
	LocalTimeName = "localtime"

	VarRunTls = "/var/run/tls"
	TlsName   = "kube-ovn-tls"

	SystemdPath = "/lib/systemd/system"
	SystemdName = "host-run-systemd"
)

// DebuggerReconciler reconciles a Debugger object
type DebuggerReconciler struct {
	client.Client
	Scheme     *runtime.Scheme
	KubeClient kubernetes.Interface
	RestConfig *rest.Config
	Log        logr.Logger
	Namespace  string
	Reload     chan event.GenericEvent
}

// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=debuggers,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=debuggers/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=debuggers/finalizers,verbs=update
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=pingers,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=pingers/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=pingers/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=apps,resources=deployments/scale,verbs=get;watch;update
// +kubebuilder:rbac:groups=apps,resources=deployments/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments/finalizers,verbs=get;list;watch
// +kubebuilder:rbac:groups=apps,resources=daemonsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=apps,resources=daemonsets/scale,verbs=get;watch;update
// +kubebuilder:rbac:groups=apps,resources=daemonsets/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=daemonsets/finalizers,verbs=get;list;watch
// +kubebuilder:rbac:groups=core,resources=pods,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=pods/exec,verbs=create
// +kubebuilder:rbac:groups=core,resources=pods/log,verbs=get
// +kubebuilder:rbac:groups=core,resources=nodes,verbs=get;list

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the Debugger object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.19.0/pkg/reconcile
func (r *DebuggerReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = log.FromContext(ctx)

	// TODO(user): your logic here
	// delete debugger itself, its owned deploy will be deleted automatically
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start reconcile", "debugger", namespacedName)
	defer r.Log.Info("end reconcile", "debugger", namespacedName)
	updates.Inc()
	res, err := r.handleAddOrUpdateDebugger(ctx, req)
	switch res {
	case SyncStateError:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle debugger, will retry")
		return ctrl.Result{RequeueAfter: 3 * time.Second}, errRetry
	case SyncStateErrorNoRetry:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle debugger, not retry")
		return ctrl.Result{}, nil
	}
	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *DebuggerReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&myv1.Debugger{},
			builder.WithPredicates(
				predicate.NewPredicateFuncs(
					func(object client.Object) bool {
						_, ok := object.(*myv1.Debugger)
						if !ok {
							err := errors.New("invalid debugger")
							r.Log.Error(err, "expected debugger in workqueue but got something else")
							return false
						}
						return true
					},
				),
			),
		).
		Owns(&appsv1.DaemonSet{}).  // for all node pod case
		Owns(&appsv1.Deployment{}). // for single pod case
		Owns(&myv1.Pinger{}).
		Complete(r)
}

func (r *DebuggerReconciler) handleAddOrUpdateDebugger(ctx context.Context, req ctrl.Request) (SyncState, error) {
	// Implement the logic to handle the addition or update of a Debugger resource
	// create debugger daemonset or deployment
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start handleAddOrUpdateDebugger", "debugger", namespacedName)
	defer r.Log.Info("end handleAddOrUpdateDebugger", "debugger", namespacedName)

	// fetch debugger
	debugger, err := r.getDebugger(ctx, req.NamespacedName)
	if err != nil {
		r.Log.Error(err, "failed to get debugger")
		return SyncStateErrorNoRetry, err
	}
	if debugger == nil {
		// debugger deleted
		return SyncStateSuccess, nil
	}
	if err := r.validateDebugger(debugger); err != nil {
		r.Log.Error(err, "failed to validate debugger")
		// invalid spec, no retry
		return SyncStateErrorNoRetry, err
	}

	if debugger.Spec.ConfigMap != "" {
		cmName := debugger.Spec.ConfigMap
		cm, err := r.KubeClient.CoreV1().ConfigMaps(debugger.Namespace).Get(context.TODO(), cmName, metav1.GetOptions{})
		if err != nil {
			r.Log.Error(err, "failed to get config map", "configMap", cmName)
			return SyncStateError, err
		}
		if cm.Data == nil {
			err := fmt.Errorf("config map %s is empty", cmName)
			r.Log.Error(err, "should not set empty config map")
			return SyncStateErrorNoRetry, err
		}
	}

	var pinger *myv1.Pinger
	if debugger.Spec.Pinger != "" {
		pinger = &myv1.Pinger{
			ObjectMeta: metav1.ObjectMeta{
				Name:      debugger.Spec.Pinger,
				Namespace: debugger.Namespace,
			},
		}
		pinger, err = r.getPinger(ctx, pinger)
		if err != nil {
			r.Log.Error(err, "failed to get pinger")
			return SyncStateError, err
		}
		if err := r.validatePinger(pinger, debugger.Spec.EnablePinger); err != nil {
			r.Log.Error(err, "failed to validate pinger")
			// invalid spec no retry
			return SyncStateErrorNoRetry, err
		}
	}

	change := r.isChanged(debugger)
	if !change {
		r.Log.Info("debugger is up to date, no need to sync", "debugger", debugger.Name)
		return SyncStateSuccess, nil
	}

	// create debugger or update
	if debugger.Spec.WorkloadType == WorkloadTypePod {
		// deployment for one pod case
		if err := r.handleAddOrUpdatePod(req, debugger, pinger); err != nil {
			r.Log.Error(err, "failed to handleAddOrUpdateDeploy")
			return SyncStateError, err
		}
	} else {
		// daemonset for all node case
		if err := r.handleAddOrUpdateDaemonset(req, debugger, pinger); err != nil {
			r.Log.Error(err, "failed to handleAddOrUpdateDaemonset")
			return SyncStateError, err
		}
	}

	if err := r.UpdateDebugger(ctx, req, debugger); err != nil {
		r.Log.Error(err, "failed to update debugger status")
		return SyncStateError, err
	}
	return SyncStateSuccess, nil
}

func (r *DebuggerReconciler) UpdateDebugger(ctx context.Context, req ctrl.Request, debugger *myv1.Debugger) error {
	if debugger == nil {
		return nil
	}
	changed := false
	newDebugger := debugger.DeepCopy()
	if debugger.Spec.CPU != debugger.Status.CPU {
		newDebugger.Status.CPU = debugger.Spec.CPU
		changed = true
	}
	if debugger.Spec.Memory != debugger.Status.Memory {
		newDebugger.Status.Memory = debugger.Spec.Memory
		changed = true
	}
	if debugger.Spec.Image != debugger.Status.Image {
		newDebugger.Status.Image = debugger.Spec.Image
		changed = true
	}
	if debugger.Spec.QoSBandwidth != debugger.Status.QoSBandwidth {
		newDebugger.Status.QoSBandwidth = debugger.Spec.QoSBandwidth
		changed = true
	}
	if debugger.Spec.WorkloadType != debugger.Status.WorkloadType {
		newDebugger.Status.WorkloadType = debugger.Spec.WorkloadType
		changed = true
	}
	if debugger.Spec.EnablePinger != debugger.Status.EnablePinger {
		newDebugger.Status.EnablePinger = debugger.Spec.EnablePinger
		changed = true
	}
	if debugger.Spec.Pinger != debugger.Status.Pinger {
		newDebugger.Status.Pinger = debugger.Spec.Pinger
		changed = true
	}
	if !reflect.DeepEqual(debugger.Spec.Tolerations, debugger.Status.Tolerations) {
		newDebugger.Status.Tolerations = debugger.Spec.Tolerations
		changed = true
	}
	if !reflect.DeepEqual(debugger.Spec.Affinity, debugger.Status.Affinity) {
		newDebugger.Status.Affinity = debugger.Spec.Affinity
		changed = true
	}
	if debugger.Spec.NodeName != debugger.Status.NodeName {
		newDebugger.Status.NodeName = debugger.Spec.NodeName
		changed = true
	}
	if debugger.Spec.HostNetwork != debugger.Status.HostNetwork {
		newDebugger.Status.HostNetwork = debugger.Spec.HostNetwork
		changed = true
	}
	if !changed {
		return nil
	}
	if err := r.Status().Update(context.Background(), newDebugger); err != nil {
		r.Log.Error(err, "failed to update debugger status")
		return err
	}
	return nil
}

func (r *DebuggerReconciler) getDebugger(ctx context.Context, name types.NamespacedName) (*myv1.Debugger, error) {
	var res myv1.Debugger
	err := r.Get(ctx, name, &res)
	if apierrors.IsNotFound(err) {
		// in case of delete
		return nil, nil
	}
	if err != nil {
		r.Log.Error(err, "failed to get debugger")
		return nil, err
	}
	return &res, nil
}

func (r *DebuggerReconciler) getPinger(ctx context.Context, pinger *myv1.Pinger) (*myv1.Pinger, error) {
	var res myv1.Pinger
	name := types.NamespacedName{
		Name:      pinger.Name,
		Namespace: pinger.Namespace,
	}
	err := r.Get(ctx, name, &res)
	if err != nil {
		r.Log.Error(err, "failed to get pinger")
		return nil, err
	}

	return &res, nil
}

func (r *DebuggerReconciler) validateDebugger(debugger *myv1.Debugger) error {
	r.Log.V(3).Info("start validateDebugger", "debugger", debugger)
	if debugger.Spec.CPU == "" {
		err := errors.New("debugger pod cpu is required")
		r.Log.Error(err, "should set cpu")
		return err
	}
	if debugger.Spec.Memory == "" {
		err := errors.New("debugger pod memory is required")
		r.Log.Error(err, "should set memory")
		return err
	}
	if debugger.Spec.Image == "" {
		err := fmt.Errorf("debugger %s image is required", debugger.Name)
		r.Log.Error(err, "should set image")
		return err
	}

	if debugger.Spec.WorkloadType == "" {
		err := errors.New("debugger workload type is required")
		r.Log.Error(err, "should set workload type")
		return err
	}
	if debugger.Spec.WorkloadType != WorkloadTypeDaemonset && debugger.Spec.WorkloadType != WorkloadTypePod {
		err := fmt.Errorf("debugger %s workload type is invalid, should be daemonset or pod", debugger.Name)
		r.Log.Error(err, "should set valid workload type")
		return err
	}

	if debugger.Spec.WorkloadType == WorkloadTypeDaemonset {
		if debugger.Spec.NodeName != "" {
			err := fmt.Errorf("debugger %s daemonset not need node name", debugger.Name)
			r.Log.Error(err, "should not set node name for daemonset debugger pod")
			return err
		}
	}

	if debugger.Spec.EnableConfigMap && debugger.Spec.ConfigMap == "" {
		err := fmt.Errorf("debugger %s enable config map, but config map is empty", debugger.Name)
		r.Log.Error(err, "should set config map")
		return err
	}

	if debugger.Spec.EnablePinger && debugger.Spec.Pinger == "" {
		err := fmt.Errorf("debugger %s enable pinger, but pinger is empty", debugger.Name)
		r.Log.Error(err, "should set pinger info")
		return err
	}

	if debugger.Status.Subnet != "" && debugger.Status.Subnet != debugger.Spec.Subnet {
		err := fmt.Errorf("debugger %s subnet is changed, old: %s, new: %s", debugger.Name, debugger.Status.Subnet, debugger.Spec.Subnet)
		r.Log.Error(err, "should not change subnet")
		return err
	}

	if debugger.Spec.HostNetwork && debugger.Spec.Subnet != "" {
		err := fmt.Errorf("debugger %s use host network pod not need subnet", debugger.Name)
		r.Log.Error(err, "should not set subnet for host network pod")
		return err
	}

	return nil
}

func (r *DebuggerReconciler) validatePinger(pinger *myv1.Pinger, enablePinger bool) error {
	// 1. debugger has no pinger container, sleep infinite
	if !enablePinger {
		r.Log.Info("pinger is not enabled, skip validation", "pinger", pinger.Name)
		return nil
	}
	// 2. debugger has pinger container, check pinger spec
	if pinger.DeletionTimestamp != nil {
		// pinger is being deleted
		r.Log.Info("pinger is being deleted, skip validation", "pinger", pinger.Name)
		return nil
	}

	if pinger.Spec.Image == "" {
		err := fmt.Errorf("pinger %s image is required", pinger.Name)
		r.Log.Error(err, "should set pinger image")
		return err
	}

	if pinger.Spec.Ping == "" &&
		pinger.Spec.TcpPing == "" &&
		pinger.Spec.UdpPing == "" &&
		pinger.Spec.Dns == "" {
		err := fmt.Errorf("pinger %s must set at least one kind of ping target", pinger.Name)
		r.Log.Error(err, "should set ping task")
		return err
	}

	return nil
}

func (r *DebuggerReconciler) handleAddOrUpdatePod(req ctrl.Request, debugger *myv1.Debugger, pinger *myv1.Pinger) error {
	// create or update pod
	needToCreate := false
	oldPod := &corev1.Pod{}
	err := r.Get(context.Background(), req.NamespacedName, oldPod)
	if err != nil {
		if apierrors.IsNotFound(err) {
			needToCreate = true
		} else {
			r.Log.Error(err, "failed to get pod")
			return err
		}
	}
	newDebugger := debugger.DeepCopy()
	// create
	if needToCreate {
		// create
		newPod := r.getDebuggerPod(debugger, pinger, nil)
		err = r.Create(context.Background(), newPod)
		if err != nil {
			r.Log.Error(err, "failed to create the new pod")
			return err
		}
		time.Sleep(5 * time.Second)
		return nil
	}
	// update
	if r.isChanged(newDebugger) {
		// update
		newPod := r.getDebuggerPod(debugger, pinger, oldPod.DeepCopy())
		err = r.Update(context.Background(), newPod)
		if err != nil {
			r.Log.Error(err, "failed to update the pod")
			return err
		}
		time.Sleep(5 * time.Second)
		return nil
	}
	// no change
	r.Log.Info("debugger pod not changed", "debugger", debugger.Name)
	return nil
}

func (r *DebuggerReconciler) handleAddOrUpdateDaemonset(req ctrl.Request, debugger *myv1.Debugger, pinger *myv1.Pinger) error {
	// create or update daemonset
	needToCreate := false
	oldDs := &appsv1.DaemonSet{}
	err := r.Get(context.Background(), req.NamespacedName, oldDs)
	if err != nil {
		if apierrors.IsNotFound(err) {
			needToCreate = true
		} else {
			r.Log.Error(err, "failed to get daemonset")
			return err
		}
	}
	newDebugger := debugger.DeepCopy()
	// create
	if needToCreate {
		// create daemonset
		newDs := r.getDebuggerDaemonset(debugger, pinger, nil)
		err = r.Create(context.Background(), newDs)
		if err != nil {
			r.Log.Error(err, "failed to create the new daemonset")
			return err
		}
		time.Sleep(5 * time.Second)
		return nil
	}
	// update
	if r.isChanged(newDebugger) {
		// update daemonset
		newDs := r.getDebuggerDaemonset(debugger, pinger, oldDs.DeepCopy())
		err = r.Update(context.Background(), newDs)
		if err != nil {
			r.Log.Error(err, "failed to update the daemonset")
			return err
		}
		time.Sleep(5 * time.Second)
		return nil
	}
	// no change
	r.Log.Info("debugger daemonset not changed", "debugger", debugger.Name)
	return nil
}

func labelsFor(debugger *myv1.Debugger) map[string]string {
	return map[string]string{
		DebuggerName: debugger.Name,
	}
}

func (r *DebuggerReconciler) getEnvs(debugger *myv1.Debugger, pinger *myv1.Pinger) []corev1.EnvVar {
	var dsName, subnetName string
	if debugger.Spec.WorkloadType == WorkloadTypeDaemonset {
		dsName = debugger.Name
	}
	if !debugger.Spec.HostNetwork {
		subnetName = debugger.Spec.Subnet
	}
	envs := []corev1.EnvVar{
		{
			Name: "POD_NAME",
			ValueFrom: &corev1.EnvVarSource{
				FieldRef: &corev1.ObjectFieldSelector{
					FieldPath: "metadata.name",
				},
			},
		},
		{
			Name: "POD_NAMESPACE",
			ValueFrom: &corev1.EnvVarSource{
				FieldRef: &corev1.ObjectFieldSelector{
					FieldPath: "metadata.namespace",
				},
			},
		},
		{
			Name: "NODE_NAME",
			ValueFrom: &corev1.EnvVarSource{
				FieldRef: &corev1.ObjectFieldSelector{
					FieldPath: "spec.nodeName",
				},
			},
		},
		{
			Name: "POD_IP",
			ValueFrom: &corev1.EnvVarSource{
				FieldRef: &corev1.ObjectFieldSelector{
					FieldPath: "status.podIP",
				},
			},
		},
		{
			Name: "HOST_IP",
			ValueFrom: &corev1.EnvVarSource{
				FieldRef: &corev1.ObjectFieldSelector{
					FieldPath: "status.hostIP",
				},
			},
		},
		{
			Name:  "HOST_NETWORK",
			Value: strconv.FormatBool(debugger.Spec.HostNetwork),
		},
		{
			Name:  "HOST_CHECK_LIST",
			Value: strconv.FormatBool(debugger.Spec.HostCheckList),
		},
		{
			Name:  "DS_NAME",
			Value: dsName,
		},
		{
			Name:  Subnet,
			Value: subnetName,
		},
	}
	// pinger envs
	if pinger != nil {
		pingerEnvs := []corev1.EnvVar{
			{
				Name:  EnableMetrics,
				Value: strconv.FormatBool(pinger.Spec.EnableMetrics),
			},
			{
				Name:  Ping,
				Value: pinger.Spec.Ping,
			},
			{
				Name:  TcpPing,
				Value: pinger.Spec.TcpPing,
			},
			{
				Name:  UdpPing,
				Value: pinger.Spec.UdpPing,
			},
			{
				Name:  Dns,
				Value: pinger.Spec.Dns,
			},
		}
		envs = append(envs, pingerEnvs...)
	}
	return envs
}
func (r *DebuggerReconciler) getVolumesMounts(debugger *myv1.Debugger) ([]corev1.Volume, []corev1.VolumeMount) {
	volumes := []corev1.Volume{
		{
			Name: OpenvswitchName,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: VarRunOpenvswitch,
				},
			},
		},
		{
			Name: OvnName,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: VarRunOvn,
				},
			},
		},
		{
			Name: OpenvswitchConfig,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: EtcOpenvswitch,
				},
			},
		},
		{
			Name: OpenvswitchLog,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: VarLogOpenvswitch,
				},
			},
		},
		{
			Name: OvnLog,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: VarLogOvn,
				},
			},
		},
		{
			Name: KubeOvnLog,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: VarLogKubeOvn,
				},
			},
		},
		{
			Name: KubeComboLog,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: VarLogKubeCombo,
				},
			},
		},
		{
			Name: LocalTimeName,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: EtcLocalTime,
				},
			},
		},
		{
			Name: SystemdName,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: SystemdPath,
				},
			},
		},
		{
			Name: TlsName,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: VarRunTls,
				},
			},
		},
	}

	volumeMounts := []corev1.VolumeMount{
		{
			Name:      OpenvswitchName,
			MountPath: VarRunOpenvswitch,
		},
		{
			Name:      OvnName,
			MountPath: VarRunOvn,
		},
		{
			Name:      OpenvswitchConfig,
			MountPath: EtcOpenvswitch,
		},
		{
			Name:      OpenvswitchLog,
			MountPath: VarLogOpenvswitch,
		},
		{
			Name:      OvnLog,
			MountPath: VarLogOvn,
		},
		{
			Name:      KubeOvnLog,
			MountPath: VarLogKubeOvn,
		},
		{
			Name:      KubeComboLog,
			MountPath: VarLogKubeCombo,
		},
		{
			Name:      LocalTimeName,
			MountPath: EtcLocalTime,
		},
		{
			Name:      SystemdName,
			MountPath: SystemdPath,
		},
		{
			Name:      TlsName,
			MountPath: VarRunTls,
		},
	}
	if debugger.Spec.EnableConfigMap && debugger.Spec.ConfigMap != "" {
		cmName := debugger.Spec.ConfigMap
		cm, err := r.KubeClient.CoreV1().ConfigMaps(debugger.Namespace).Get(context.TODO(), cmName, metav1.GetOptions{})
		if err != nil {
			r.Log.Error(err, "failed to get config map", "configMap", cmName)
			return nil, nil
		}
		scriptsVolumeMounts := []corev1.VolumeMount{}
		scriptsVolumeMounts = append(scriptsVolumeMounts, corev1.VolumeMount{
			Name:      cmName,
			MountPath: ScriptsPath,
			ReadOnly:  true,
		})
		// volumes add config map
		items := []corev1.KeyToPath{}
		for key := range cm.Data {
			if strings.HasSuffix(key, ".sh") {
				// only add script file
				items = append(items, corev1.KeyToPath{
					Key:  key,
					Path: key,
				})
			}
		}

		// add config map volumes
		// mod 0755
		mod := int32(0755)
		volumes = append(volumes, corev1.Volume{
			Name: cmName,
			VolumeSource: corev1.VolumeSource{
				ConfigMap: &corev1.ConfigMapVolumeSource{
					LocalObjectReference: corev1.LocalObjectReference{
						Name: debugger.Spec.ConfigMap,
					},
					Items:       items,
					DefaultMode: &mod,
				},
			},
		})
		// add config map volume mounts
		volumeMounts = append(volumeMounts, scriptsVolumeMounts...)
	}
	return volumes, volumeMounts
}

func (r *DebuggerReconciler) getDebuggerPod(debugger *myv1.Debugger, pinger *myv1.Pinger, oldPod *corev1.Pod) (newPod *corev1.Pod) {
	namespacedName := fmt.Sprintf("%s/%s", debugger.Namespace, debugger.Name)
	r.Log.Info("start getDebuggerPod", "debugger", namespacedName)
	defer r.Log.Info("end getDebuggerPod", "debugger", namespacedName)

	labels := labelsFor(debugger)
	newPodAnnotations := map[string]string{}
	if oldPod != nil && len(oldPod.Annotations) != 0 {
		newPodAnnotations = oldPod.Annotations
	}
	podAnnotations := map[string]string{
		KubeovnLogicalSwitchAnnotation: debugger.Spec.Subnet,
		KubeovnIngressRateAnnotation:   debugger.Spec.QoSBandwidth,
		KubeovnEgressRateAnnotation:    debugger.Spec.QoSBandwidth,
	}
	for key, value := range podAnnotations {
		newPodAnnotations[key] = value
	}
	volumes, volumeMounts := r.getVolumesMounts(debugger)
	envs := r.getEnvs(debugger, pinger)
	containers := []corev1.Container{}
	// debugger container
	debuggerContainer := r.getDebuggerContainer(debugger)
	debuggerContainer.VolumeMounts = volumeMounts
	debuggerContainer.Env = envs
	containers = append(containers, debuggerContainer)
	if debugger.Spec.EnablePinger {
		// pinger container
		pingerContainer := r.getPingerContainer(pinger, debugger)
		pingerContainer.VolumeMounts = volumeMounts
		pingerContainer.Env = envs
		containers = append(containers, pingerContainer)
	}
	newPod = &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:        debugger.Name,
			Namespace:   debugger.Namespace,
			Annotations: newPodAnnotations,
			Labels:      labels,
		},
		Spec: corev1.PodSpec{
			NodeName:      debugger.Spec.NodeName,
			Containers:    containers,
			Volumes:       volumes,
			RestartPolicy: corev1.RestartPolicyNever,
			HostNetwork:   debugger.Spec.HostNetwork, // host network pod
			HostPID:       debugger.Spec.HostNetwork, // host network pod see host pid
			// HostIPC:       debugger.Spec.HostNetwork, // host network pod see host ipc
			ServiceAccountName:       ServiceAccountName, // use kube-ovn service account
			DeprecatedServiceAccount: ServiceAccountName, // use kube-ovn service account
		},
	}

	// set owner reference
	if err := controllerutil.SetControllerReference(debugger, newPod, r.Scheme); err != nil {
		r.Log.Error(err, "failed to set debugger as the owner of the pod")
		return nil
	}
	return
}

func (r *DebuggerReconciler) getDebuggerContainer(debugger *myv1.Debugger) corev1.Container {
	allowPrivilegeEscalation := true
	privileged := true

	debuggerContainer := corev1.Container{
		Name:  DebuggerName,
		Image: debugger.Spec.Image,
		Resources: corev1.ResourceRequirements{
			Limits: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(debugger.Spec.CPU),
				corev1.ResourceMemory: resource.MustParse(debugger.Spec.Memory),
			},
			Requests: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(debugger.Spec.CPU),
				corev1.ResourceMemory: resource.MustParse(debugger.Spec.Memory),
			},
		},
		Command:         []string{DebuggerStartCMD},
		ImagePullPolicy: corev1.PullIfNotPresent,
		SecurityContext: &corev1.SecurityContext{
			Privileged:               &privileged,
			RunAsUser:                &[]int64{0}[0], // run as root user
			AllowPrivilegeEscalation: &allowPrivilegeEscalation,
			Capabilities: &corev1.Capabilities{
				Add: []corev1.Capability{
					"NET_ADMIN", // add net admin capability
					"NET_RAW",   // add net raw capability
				},
			},
		},
	}
	return debuggerContainer
}

func (r *DebuggerReconciler) getPingerContainer(pinger *myv1.Pinger, debugger *myv1.Debugger) corev1.Container {
	allowPrivilegeEscalation := true
	privileged := true

	pingerContainer := corev1.Container{
		Name:  PingerName,
		Image: pinger.Spec.Image,
		Resources: corev1.ResourceRequirements{
			Limits: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(debugger.Spec.CPU),
				corev1.ResourceMemory: resource.MustParse(debugger.Spec.Memory),
			},
			Requests: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(debugger.Spec.CPU),
				corev1.ResourceMemory: resource.MustParse(debugger.Spec.Memory),
			},
		},
		Command:         []string{PingerStartCMD},
		ImagePullPolicy: corev1.PullIfNotPresent,
		SecurityContext: &corev1.SecurityContext{
			Privileged:               &privileged,
			RunAsUser:                &[]int64{0}[0], // run as root user
			AllowPrivilegeEscalation: &allowPrivilegeEscalation,
			Capabilities: &corev1.Capabilities{
				Add: []corev1.Capability{
					"NET_ADMIN", // add net admin capability
					"NET_RAW",   // add net raw capability
				},
			},
		},
	}
	return pingerContainer
}
func (r *DebuggerReconciler) getDebuggerDaemonset(debugger *myv1.Debugger, pinger *myv1.Pinger, oldDs *appsv1.DaemonSet) (newDs *appsv1.DaemonSet) {
	namespacedName := fmt.Sprintf("%s/%s", debugger.Namespace, debugger.Name)
	r.Log.Info("start daemonsetForDebugger", "debugger", namespacedName)
	defer r.Log.Info("end daemonsetForDebugger", "debugger", namespacedName)

	labels := labelsFor(debugger)
	newPodAnnotations := map[string]string{}
	if oldDs != nil && len(oldDs.Annotations) != 0 {
		newPodAnnotations = oldDs.Annotations
	}
	podAnnotations := map[string]string{
		KubeovnLogicalSwitchAnnotation: debugger.Spec.Subnet,
		KubeovnIngressRateAnnotation:   debugger.Spec.QoSBandwidth,
		KubeovnEgressRateAnnotation:    debugger.Spec.QoSBandwidth,
	}
	for key, value := range podAnnotations {
		newPodAnnotations[key] = value
	}

	containers := []corev1.Container{}
	volumes, volumeMounts := r.getVolumesMounts(debugger)
	envs := r.getEnvs(debugger, pinger)
	// debugger container
	debuggerContainer := r.getDebuggerContainer(debugger)
	debuggerContainer.VolumeMounts = volumeMounts
	// append envs
	debuggerContainer.Env = envs
	containers = append(containers, debuggerContainer)
	if debugger.Spec.EnablePinger {
		// pinger container
		pingerContainer := r.getPingerContainer(pinger, debugger)
		pingerContainer.VolumeMounts = volumeMounts
		pingerContainer.Env = envs
		containers = append(containers, pingerContainer)
	}

	newDs = &appsv1.DaemonSet{
		ObjectMeta: metav1.ObjectMeta{
			Name:      debugger.Name,
			Namespace: debugger.Namespace,
			Labels:    labels,
		},
		Spec: appsv1.DaemonSetSpec{
			Selector: &metav1.LabelSelector{
				MatchLabels: labels,
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Name:        debugger.Name,
					Namespace:   debugger.Namespace,
					Labels:      labels,
					Annotations: newPodAnnotations,
				},
				Spec: corev1.PodSpec{
					Containers:  containers,
					Volumes:     volumes,
					HostNetwork: debugger.Spec.HostNetwork, // host network pod
					HostPID:     debugger.Spec.HostNetwork, // host network pod see host pid
					// HostIPC:       debugger.Spec.HostNetwork, // host network pod see host ipc
					ServiceAccountName:       ServiceAccountName, // use kube-ovn service account
					DeprecatedServiceAccount: ServiceAccountName, // use kube-ovn service account
					SecurityContext: &corev1.PodSecurityContext{
						// run as root user
						RunAsUser: &[]int64{0}[0],
					},
				},
			},
			UpdateStrategy: appsv1.DaemonSetUpdateStrategy{
				Type: appsv1.RollingUpdateDaemonSetStrategyType,
				RollingUpdate: &appsv1.RollingUpdateDaemonSet{
					MaxUnavailable: &intstr.IntOrString{
						IntVal: 1, // allow one pod unavailable during update
						StrVal: "1",
					},
				},
			},
		},
	}

	if len(debugger.Spec.Selector) > 0 {
		selectors := make(map[string]string)
		for _, v := range debugger.Spec.Selector {
			parts := strings.Split(strings.TrimSpace(v), ":")
			if len(parts) != 2 {
				continue
			}
			selectors[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
		newDs.Spec.Template.Spec.NodeSelector = selectors
	}

	if len(debugger.Spec.Tolerations) > 0 {
		newDs.Spec.Template.Spec.Tolerations = debugger.Spec.Tolerations
	}

	if debugger.Spec.Affinity.NodeAffinity != nil ||
		debugger.Spec.Affinity.PodAffinity != nil ||
		debugger.Spec.Affinity.PodAntiAffinity != nil {
		newDs.Spec.Template.Spec.Affinity = &debugger.Spec.Affinity
	}

	// set owner reference
	if err := controllerutil.SetControllerReference(debugger, newDs, r.Scheme); err != nil {
		r.Log.Error(err, "failed to set debugger as the owner of the daemonset")
		// if we cannot set owner reference, we cannot manage this daemonset
		// so we return nil to skip this daemonset
		return nil
	}
	return newDs
}

func (r *DebuggerReconciler) isChanged(debugger *myv1.Debugger) bool {
	if debugger == nil {
		return false
	}
	if debugger.Spec.CPU != debugger.Status.CPU ||
		debugger.Spec.Memory != debugger.Status.Memory ||
		debugger.Spec.Image != debugger.Status.Image ||
		debugger.Spec.QoSBandwidth != debugger.Status.QoSBandwidth ||
		debugger.Spec.WorkloadType != debugger.Status.WorkloadType ||
		debugger.Spec.EnableConfigMap != debugger.Status.EnableConfigMap ||
		debugger.Spec.ConfigMap != debugger.Status.ConfigMap ||
		debugger.Spec.EnablePinger != debugger.Status.EnablePinger ||
		debugger.Spec.HostCheckList != debugger.Status.HostCheckList ||
		debugger.Spec.Pinger != debugger.Status.Pinger {
		return true
	}
	if !reflect.DeepEqual(debugger.Spec.Tolerations, debugger.Status.Tolerations) {
		return true
	}
	if !reflect.DeepEqual(debugger.Spec.Affinity, debugger.Status.Affinity) {
		return true
	}
	if debugger.Spec.NodeName != debugger.Status.NodeName {
		return true
	}
	if debugger.Spec.HostNetwork != debugger.Status.HostNetwork {
		return true
	}
	return false
}
