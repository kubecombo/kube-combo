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
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	vpngwv1 "github.com/kubecombo/kube-combo/api/v1"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// ssl vpn openvpn
const (
	SslVpnServer     = "ssl"
	SslVpnUdpPort    = 1194
	SslVpnTcpPort    = 443
	SslVpnSecretPath = "/etc/openvpn/certmanager"
	DhSecretPath     = "/etc/openvpn/dh"

	SslVpnStartUpCMD = "/etc/openvpn/setup/configure.sh"

	// debug daemonset ssl vpn pod need sleep infinity
	SslVpnDebugCMD = "/etc/openvpn/setup/debug.sh"

	EnableSslVpnLabel = "enable-ssl-vpn"

	// vpn gw pod env
	SslVpnProtoKey      = "SSL_VPN_PROTO"
	SslVpnPortKey       = "SSL_VPN_PORT"
	SslVpnCipherKey     = "SSL_VPN_CIPHER"
	SslVpnAuthKey       = "SSL_VPN_AUTH"
	SslVpnSubnetCidrKey = "SSL_VPN_SUBNET_CIDR"
)

// ipsec vpn strongswan
const (
	IpsecVpnServer = "ipsec"

	IpsecVpnLocalPortKey  = "ipsec-local"
	IpsecVpnRemotePortKey = "ipsec-remote"

	IpsecVpnSecretPath = "/etc/ipsec/certs"

	IpsecVpnStartUpCMD             = "/usr/sbin/charon-systemd"
	IpsecConnectionRefreshTemplate = "/connection.sh refresh %s"

	EnableIpsecVpnLabel = "enable-ipsec-vpn"

	IpSecBootPcPortKey = "bootpc"
	IpSecBootPcPort    = 68
	IpSecIsakmpPortKey = "isakmp"
	IpSecIsakmpPort    = 500
	IpSecNatPortKey    = "nat"
	IpSecNatPort       = 4500

	IpsecProto = "UDP"

	// IpsecRemoteAddrsKey = "IPSEC_REMOTE_ADDRS"
	// IpsecRemoteTsKey    = "IPSEC_REMOTE_TS"
)

// keepalived
const (
	KeepalivedVipKey          = "KEEPALIVED_VIP"
	keepalivedVirtualRouterID = "KEEPALIVED_VIRTUAL_ROUTER_ID"
	KeepalivedStartUpCMD      = "/configure.sh"
	KeepAlivedServer          = "keepalived"
)

// VpnGwReconciler reconciles a VpnGw object
type VpnGwReconciler struct {
	client.Client
	Scheme     *runtime.Scheme
	KubeClient kubernetes.Interface
	RestConfig *rest.Config
	Log        logr.Logger
	Namespace  string
	Reload     chan event.GenericEvent
}

// Note: you need a blank line after this list in order for the controller to pick this up.

// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=vpngws,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=vpngws/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=vpngws/finalizers,verbs=update
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=ipsecconns,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=ipsecconns/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=ipsecconns/finalizers,verbs=update
// +kubebuilder:rbac:groups=core,resources=secrets,verbs=get;list;watch;create;update;patch
// +kubebuilder:rbac:groups=apps,resources=statefulsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=apps,resources=statefulsets/scale,verbs=get;watch;update
// +kubebuilder:rbac:groups=apps,resources=statefulsets/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=statefulsets/finalizers,verbs=get;list;watch
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
// the VpnGw object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.14.1/pkg/reconcile
func (r *VpnGwReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = log.FromContext(ctx)

	// TODO(user): your logic here
	// delete vpn gw itself, its owned statefulset will be deleted automatically
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start reconcile", "vpn gw", namespacedName)
	defer r.Log.Info("end reconcile", "vpn gw", namespacedName)
	updates.Inc()
	res, err := r.handleAddOrUpdateVpnGw(ctx, req)
	switch res {
	case SyncStateError:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle vpn gw, will retry")
		return ctrl.Result{RequeueAfter: 3 * time.Second}, errRetry
	case SyncStateErrorNoRetry:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle vpn gw, will not retry")
		return ctrl.Result{}, nil
	}
	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *VpnGwReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&vpngwv1.VpnGw{},
			builder.WithPredicates(
				predicate.NewPredicateFuncs(
					func(object client.Object) bool {
						_, ok := object.(*vpngwv1.VpnGw)
						if !ok {
							err := errors.New("invalid vpn gw")
							r.Log.Error(err, "expected vpn gw in worequeue but got something else")
							return false
						}
						return true
					},
				),
			),
		).
		Owns(&appsv1.StatefulSet{}).
		Owns(&vpngwv1.IpsecConn{}).
		Owns(&vpngwv1.KeepAlived{}).
		Complete(r)
}

func (r *VpnGwReconciler) validateKeepalived(ka *vpngwv1.KeepAlived) error {
	if ka.Spec.Image == "" {
		err := fmt.Errorf("keepalived image is required")
		r.Log.Error(err, "should set keepalived image")
		return err
	}
	if ka.Spec.Subnet == "" {
		err := fmt.Errorf("keepalived subnet is required")
		r.Log.Error(err, "should set keepalived subnet")
		return err
	}
	if ka.Spec.VipV4 == "" && ka.Spec.VipV6 == "" {
		err := fmt.Errorf("keepalived vip v4 or v6 ip is required")
		r.Log.Error(err, "should set keepalived vip")
		return err
	}
	return nil
}

func (r *VpnGwReconciler) validateVpnGw(gw *vpngwv1.VpnGw) error {
	r.Log.V(3).Info("start validateVpnGw", "vpn gw", gw)
	if gw.Spec.Keepalived == "" {
		err := fmt.Errorf("vpn gw keepalived is required")
		r.Log.Error(err, "should set keepalived")
		return err
	}

	if gw.Spec.Cpu == "" || gw.Spec.Memory == "" {
		err := fmt.Errorf("vpn gw cpu and memory is required")
		r.Log.Error(err, "should set cpu and memory")
		return err
	}

	if gw.Spec.QoSBandwidth == "" || gw.Spec.QoSBandwidth == "0" {
		err := fmt.Errorf("vpn gw qos bandwidth is required")
		r.Log.Error(err, "should set qos bandwidth")
		return err
	}

	if !gw.Spec.EnableSslVpn && !gw.Spec.EnableIpsecVpn {
		err := fmt.Errorf("either ssl vpn or ipsec vpn should be enabled")
		r.Log.Error(err, "vpn gw spec should enable ssl vpn or ipsec vpn")
		return err
	}

	if gw.Spec.EnableSslVpn {
		if gw.Spec.SslVpnSecret == "" {
			err := fmt.Errorf("ssl vpn secret is required")
			r.Log.Error(err, "should set ssl vpn secret")
			return err
		}
		if gw.Spec.DhSecret == "" {
			err := fmt.Errorf("ssl vpn dh secret is required")
			r.Log.Error(err, "should set ssl vpn dh secret")
			return err
		}
		if gw.Spec.SslVpnCipher == "" {
			err := fmt.Errorf("ssl vpn cipher is required")
			r.Log.Error(err, "should set cipher")
			return err
		}
		if gw.Spec.SslVpnProto == "" {
			err := fmt.Errorf("ssl vpn proto is required")
			r.Log.Error(err, "should set ssl vpn proto")
			return err
		}
		if gw.Spec.SslVpnSubnetCidr == "" {
			err := fmt.Errorf("ssl vpn subnet cidr is required")
			r.Log.Error(err, "should set ssl vpn client and server subnet")
			return err
		}
		if gw.Spec.SslVpnProto != "udp" && gw.Spec.SslVpnProto != "tcp" {
			err := fmt.Errorf("ssl vpn proto should be udp or tcp")
			r.Log.Error(err, "should set reasonable vpn proto")
			return err
		}
		if gw.Spec.SslVpnImage == "" {
			err := fmt.Errorf("ssl vpn image is required")
			r.Log.Error(err, "should set ssl vpn image")
			return err
		}
	}

	if gw.Spec.EnableIpsecVpn {
		if gw.Spec.IpsecSecret == "" {
			err := fmt.Errorf("ipsec vpn secret is required")
			r.Log.Error(err, "should set ipsec vpn secret")
			return err
		}
		if gw.Spec.IpsecVpnImage == "" {
			err := fmt.Errorf("ipsec vpn image is required")
			r.Log.Error(err, "should set ipsec vpn image")
			return err
		}
	}
	return nil
}

func (r *VpnGwReconciler) isChanged(gw *vpngwv1.VpnGw, ipsecConnections []string) bool {
	changed := false
	if gw.Status.Keepalived == "" && gw.Spec.Keepalived != "" {
		gw.Status.Keepalived = gw.Spec.Keepalived
		changed = true
	}

	if gw.Status.Cpu != gw.Spec.Cpu {
		gw.Status.Cpu = gw.Spec.Cpu
		changed = true
	}
	if gw.Status.Memory != gw.Spec.Memory {
		gw.Status.Memory = gw.Spec.Memory
		changed = true
	}
	if gw.Status.QoSBandwidth != gw.Spec.QoSBandwidth {
		gw.Status.QoSBandwidth = gw.Spec.QoSBandwidth
		changed = true
	}
	if gw.Status.Replicas != gw.Spec.Replicas {
		gw.Status.Replicas = gw.Spec.Replicas
		changed = true
	}

	if gw.Status.EnableSslVpn != gw.Spec.EnableSslVpn {
		gw.Status.EnableSslVpn = gw.Spec.EnableSslVpn
		if gw.Status.SslVpnCipher != gw.Spec.SslVpnCipher {
			gw.Status.SslVpnCipher = gw.Spec.SslVpnCipher
		}
		if gw.Status.SslVpnProto != gw.Spec.SslVpnProto {
			gw.Status.SslVpnProto = gw.Spec.SslVpnProto
		}
		if gw.Status.SslVpnSubnetCidr != gw.Spec.SslVpnSubnetCidr {
			gw.Status.SslVpnSubnetCidr = gw.Spec.SslVpnSubnetCidr
		}
		if gw.Status.SslVpnImage != gw.Spec.SslVpnImage {
			gw.Status.SslVpnImage = gw.Spec.SslVpnImage
		}
		changed = true
	}

	if gw.Status.EnableIpsecVpn != gw.Spec.EnableIpsecVpn {
		gw.Status.EnableIpsecVpn = gw.Spec.EnableIpsecVpn
		if gw.Status.IpsecVpnImage != gw.Spec.IpsecVpnImage {
			gw.Status.IpsecVpnImage = gw.Spec.IpsecVpnImage
		}
		changed = true
	}

	if gw.Status.EnableIpsecVpn && ipsecConnections != nil {
		if !reflect.DeepEqual(gw.Spec.IpsecConnections, ipsecConnections) {
			gw.Spec.IpsecConnections = ipsecConnections
			gw.Status.IpsecConnections = ipsecConnections
		}
		changed = true
	}

	if !reflect.DeepEqual(gw.Spec.Selector, gw.Status.Selector) {
		gw.Status.Selector = gw.Spec.Selector
		changed = true
	}
	if !reflect.DeepEqual(gw.Spec.Tolerations, gw.Status.Tolerations) {
		gw.Status.Tolerations = gw.Spec.Tolerations
		changed = true
	}
	if !reflect.DeepEqual(gw.Spec.Affinity, gw.Status.Affinity) {
		gw.Status.Affinity = gw.Spec.Affinity
		changed = true
	}
	return changed
}

func (r *VpnGwReconciler) statefulSetForVpnGw(gw *vpngwv1.VpnGw, ka *vpngwv1.KeepAlived, oldSts *appsv1.StatefulSet) (newSts *appsv1.StatefulSet) {
	namespacedName := fmt.Sprintf("%s/%s", gw.Namespace, gw.Name)
	r.Log.Info("start statefulSetForVpnGw", "vpn gw", namespacedName)
	defer r.Log.Info("end statefulSetForVpnGw", "vpn gw", namespacedName)
	replicas := gw.Spec.Replicas
	// TODO: HA may use router lb external eip as fontend
	allowPrivilegeEscalation := true
	privileged := true
	labels := labelsForVpnGw(gw)
	newPodAnnotations := map[string]string{}
	if oldSts != nil && len(oldSts.Annotations) != 0 {
		newPodAnnotations = oldSts.Annotations
	}
	podAnnotations := map[string]string{
		KubeovnLogicalSwitchAnnotation: ka.Spec.Subnet,
		KubeovnIngressRateAnnotation:   gw.Spec.QoSBandwidth,
		KubeovnEgressRateAnnotation:    gw.Spec.QoSBandwidth,
	}
	for key, value := range podAnnotations {
		newPodAnnotations[key] = value
	}

	containers := []corev1.Container{}
	volumes := []corev1.Volume{}

	// keepalived
	keepalivedContainer := corev1.Container{
		Name:  KeepAlivedServer,
		Image: ka.Spec.Image,
		Resources: corev1.ResourceRequirements{
			Requests: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
				corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
			},
			Limits: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
				corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
			},
		},
		Command: []string{KeepalivedStartUpCMD},
		Env: []corev1.EnvVar{
			{
				Name:  KeepalivedVipKey,
				Value: ka.Spec.VipV4,
			},
			{
				Name:  keepalivedVirtualRouterID,
				Value: strconv.Itoa(ka.Status.RouterID),
			},
		},
		ImagePullPolicy: corev1.PullIfNotPresent,
		SecurityContext: &corev1.SecurityContext{
			Privileged:               &privileged,
			AllowPrivilegeEscalation: &allowPrivilegeEscalation,
		},
	}

	if gw.Spec.EnableSslVpn {
		// config ssl vpn openvpn pod：
		// port, proto, cipher, auth, subnet
		// volume: x.509 secret, dhparams secret
		// env: proto, port, cipher, auth, subnet
		// command: openvpn --config /etc/openvpn/server.conf
		cmd := []string{SslVpnStartUpCMD}
		if gw.Spec.WorkloadType == "static" {
			// debug daemonset ssl vpn pod need sleep infinity
			cmd = []string{SslVpnDebugCMD}
		}
		sslVpnPort := SslVpnUdpPort
		if gw.Spec.SslVpnProto == "tcp" {
			sslVpnPort = SslVpnTcpPort
		}

		sslContainer := corev1.Container{
			Name:  SslVpnServer,
			Image: gw.Spec.SslVpnImage,
			VolumeMounts: []corev1.VolumeMount{
				// mount x.509 secret
				{
					Name:      gw.Spec.SslVpnSecret,
					MountPath: SslVpnSecretPath,
					ReadOnly:  true,
				},
				// mount openssl dhparams secret
				{
					Name:      gw.Spec.DhSecret,
					MountPath: DhSecretPath,
					ReadOnly:  true,
				},
			},
			Resources: corev1.ResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
				Limits: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
			},
			Command: cmd,
			Ports: []corev1.ContainerPort{{
				ContainerPort: int32(sslVpnPort),
				Name:          SslVpnServer,
				Protocol:      corev1.Protocol(strings.ToUpper(gw.Spec.SslVpnProto)),
			}},
			Env: []corev1.EnvVar{
				{
					Name:  SslVpnProtoKey,
					Value: gw.Spec.SslVpnProto,
				},
				{
					Name:  SslVpnPortKey,
					Value: strconv.Itoa(sslVpnPort),
				},
				{
					Name:  SslVpnCipherKey,
					Value: gw.Spec.SslVpnCipher,
				},
				{
					Name:  SslVpnAuthKey,
					Value: gw.Spec.SslVpnAuth,
				},
				{
					Name:  SslVpnSubnetCidrKey,
					Value: gw.Spec.SslVpnSubnetCidr,
				},
				{
					Name:  KeepalivedVipKey,
					Value: ka.Spec.VipV4,
				},
			},
			ImagePullPolicy: corev1.PullIfNotPresent,
			SecurityContext: &corev1.SecurityContext{
				Privileged:               &privileged,
				AllowPrivilegeEscalation: &allowPrivilegeEscalation,
			},
		}
		sslSecretVolume := corev1.Volume{
			Name: gw.Spec.SslVpnSecret,
			// define secrect volume
			VolumeSource: corev1.VolumeSource{
				Secret: &corev1.SecretVolumeSource{
					SecretName: gw.Spec.SslVpnSecret,
					Optional:   &[]bool{true}[0],
				},
			},
		}
		volumes = append(volumes, sslSecretVolume)
		dhSecretVolume := corev1.Volume{
			Name: gw.Spec.DhSecret,
			// define secrect volume
			VolumeSource: corev1.VolumeSource{
				Secret: &corev1.SecretVolumeSource{
					SecretName: gw.Spec.DhSecret,
					Optional:   &[]bool{true}[0],
				},
			},
		}
		volumes = append(volumes, dhSecretVolume)
		containers = append(containers, sslContainer)
	}
	if gw.Spec.EnableIpsecVpn {
		// config ipsec vpn strongswan pod:
		// port, proto
		// volume: x.509 secret
		// env: proto, port
		// command: ipsec start
		ipsecContainer := corev1.Container{
			Name:  IpsecVpnServer,
			Image: gw.Spec.IpsecVpnImage,
			// mount x.509 secret
			VolumeMounts: []corev1.VolumeMount{
				{
					Name:      gw.Spec.IpsecSecret,
					MountPath: IpsecVpnSecretPath,
					ReadOnly:  true,
				},
			},
			Resources: corev1.ResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
				Limits: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
			},
			Command: []string{IpsecVpnStartUpCMD},
			Ports: []corev1.ContainerPort{
				{
					ContainerPort: IpSecIsakmpPort,
					Name:          IpSecIsakmpPortKey,
					Protocol:      corev1.Protocol(IpsecProto),
				},
				{
					ContainerPort: IpSecBootPcPort,
					Name:          IpSecBootPcPortKey,
					Protocol:      corev1.Protocol(IpsecProto),
				},
				{
					ContainerPort: IpSecNatPort,
					Name:          IpSecNatPortKey,
					Protocol:      corev1.Protocol(IpsecProto)},
			},
			ImagePullPolicy: corev1.PullIfNotPresent,
			SecurityContext: &corev1.SecurityContext{
				Privileged:               &privileged,
				AllowPrivilegeEscalation: &allowPrivilegeEscalation,
			},
		}
		ipsecSecretVolume := corev1.Volume{
			// define secrect volume
			Name: gw.Spec.IpsecSecret,
			VolumeSource: corev1.VolumeSource{
				Secret: &corev1.SecretVolumeSource{
					SecretName: gw.Spec.IpsecSecret,
					Optional:   &[]bool{true}[0],
				},
			},
		}
		volumes = append(volumes, ipsecSecretVolume)
		containers = append(containers, ipsecContainer)
	}
	containers = append(containers, keepalivedContainer)
	newSts = &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{
			Name:      gw.Name,
			Namespace: gw.Namespace,
			Labels:    labels,
		},
		Spec: appsv1.StatefulSetSpec{
			Replicas: &replicas,
			Selector: &metav1.LabelSelector{
				MatchLabels: labels,
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels:      labels,
					Annotations: newPodAnnotations,
				},
				Spec: corev1.PodSpec{
					Containers: containers,
					Volumes:    volumes,
				},
			},
			UpdateStrategy: appsv1.StatefulSetUpdateStrategy{
				Type: appsv1.RollingUpdateStatefulSetStrategyType,
			},
		},
	}

	if len(gw.Spec.Selector) > 0 {
		selectors := make(map[string]string)
		for _, v := range gw.Spec.Selector {
			parts := strings.Split(strings.TrimSpace(v), ":")
			if len(parts) != 2 {
				continue
			}
			selectors[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
		newSts.Spec.Template.Spec.NodeSelector = selectors
	}

	if len(gw.Spec.Tolerations) > 0 {
		newSts.Spec.Template.Spec.Tolerations = gw.Spec.Tolerations
	}

	if gw.Spec.Affinity.NodeAffinity != nil ||
		gw.Spec.Affinity.PodAffinity != nil ||
		gw.Spec.Affinity.PodAntiAffinity != nil {
		newSts.Spec.Template.Spec.Affinity = &gw.Spec.Affinity
	}

	// set gw instance as the owner and controller
	if err := controllerutil.SetControllerReference(gw, newSts, r.Scheme); err != nil {
		r.Log.Error(err, "failed to set vpn gw as the owner and controller")
		return nil
	}
	return
}

func (r *VpnGwReconciler) daemonsetForVpnGw(gw *vpngwv1.VpnGw, ka *vpngwv1.KeepAlived, oldDs *appsv1.DaemonSet) (newDs *appsv1.DaemonSet) {
	namespacedName := fmt.Sprintf("%s/%s", gw.Namespace, gw.Name)
	r.Log.Info("start daemonsetForVpnGw", "vpn gw", namespacedName)
	defer r.Log.Info("end daemonsetForVpnGw", "vpn gw", namespacedName)
	// TODO: HA may use router lb external eip as fontend
	allowPrivilegeEscalation := true
	privileged := true
	labels := labelsForVpnGw(gw)
	newPodAnnotations := map[string]string{}
	if oldDs != nil && len(oldDs.Annotations) != 0 {
		newPodAnnotations = oldDs.Annotations
	}
	podAnnotations := map[string]string{
		KubeovnLogicalSwitchAnnotation: ka.Spec.Subnet,
		KubeovnIngressRateAnnotation:   gw.Spec.QoSBandwidth,
		KubeovnEgressRateAnnotation:    gw.Spec.QoSBandwidth,
	}
	for key, value := range podAnnotations {
		newPodAnnotations[key] = value
	}

	containers := []corev1.Container{}
	volumes := []corev1.Volume{}

	// keepalived
	keepalivedContainer := corev1.Container{
		Name:  KeepAlivedServer,
		Image: ka.Spec.Image,
		Resources: corev1.ResourceRequirements{
			Requests: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
				corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
			},
			Limits: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
				corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
			},
		},
		Command: []string{KeepalivedStartUpCMD},
		Env: []corev1.EnvVar{
			{
				Name:  KeepalivedVipKey,
				Value: ka.Spec.VipV4,
			},
			{
				Name:  keepalivedVirtualRouterID,
				Value: strconv.Itoa(ka.Status.RouterID),
			},
		},
		ImagePullPolicy: corev1.PullIfNotPresent,
		SecurityContext: &corev1.SecurityContext{
			Privileged:               &privileged,
			AllowPrivilegeEscalation: &allowPrivilegeEscalation,
		},
	}

	if gw.Spec.EnableSslVpn {
		// config ssl vpn openvpn pod：
		// port, proto, cipher, auth, subnet
		// volume: x.509 secret, dhparams secret
		// env: proto, port, cipher, auth, subnet
		// command: openvpn --config /etc/openvpn/server.conf

		cmd := []string{SslVpnStartUpCMD}
		if gw.Spec.WorkloadType == "static" {
			// debug daemonset ssl vpn pod need sleep infinity
			cmd = []string{SslVpnDebugCMD}
		}
		sslVpnPort := SslVpnUdpPort
		if gw.Spec.SslVpnProto == "tcp" {
			sslVpnPort = SslVpnTcpPort
		}

		sslContainer := corev1.Container{
			Name:  SslVpnServer,
			Image: gw.Spec.SslVpnImage,
			VolumeMounts: []corev1.VolumeMount{
				// mount x.509 secret
				{
					Name:      gw.Spec.SslVpnSecret,
					MountPath: SslVpnSecretPath,
					ReadOnly:  true,
				},
				// mount openssl dhparams secret
				{
					Name:      gw.Spec.DhSecret,
					MountPath: DhSecretPath,
					ReadOnly:  true,
				},
			},
			Resources: corev1.ResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
				Limits: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
			},
			Command: cmd,
			Ports: []corev1.ContainerPort{{
				ContainerPort: int32(sslVpnPort),
				Name:          SslVpnServer,
				Protocol:      corev1.Protocol(strings.ToUpper(gw.Spec.SslVpnProto)),
			}},
			Env: []corev1.EnvVar{
				{
					Name:  SslVpnProtoKey,
					Value: gw.Spec.SslVpnProto,
				},
				{
					Name:  SslVpnPortKey,
					Value: strconv.Itoa(sslVpnPort),
				},
				{
					Name:  SslVpnCipherKey,
					Value: gw.Spec.SslVpnCipher,
				},
				{
					Name:  SslVpnAuthKey,
					Value: gw.Spec.SslVpnAuth,
				},
				{
					Name:  SslVpnSubnetCidrKey,
					Value: gw.Spec.SslVpnSubnetCidr,
				},
				{
					Name:  KeepalivedVipKey,
					Value: ka.Spec.VipV4,
				},
			},
			ImagePullPolicy: corev1.PullIfNotPresent,
			SecurityContext: &corev1.SecurityContext{
				Privileged:               &privileged,
				AllowPrivilegeEscalation: &allowPrivilegeEscalation,
			},
		}
		sslSecretVolume := corev1.Volume{
			Name: gw.Spec.SslVpnSecret,
			// define secrect volume
			VolumeSource: corev1.VolumeSource{
				Secret: &corev1.SecretVolumeSource{
					SecretName: gw.Spec.SslVpnSecret,
					Optional:   &[]bool{true}[0],
				},
			},
		}
		volumes = append(volumes, sslSecretVolume)
		dhSecretVolume := corev1.Volume{
			Name: gw.Spec.DhSecret,
			// define secrect volume
			VolumeSource: corev1.VolumeSource{
				Secret: &corev1.SecretVolumeSource{
					SecretName: gw.Spec.DhSecret,
					Optional:   &[]bool{true}[0],
				},
			},
		}
		volumes = append(volumes, dhSecretVolume)
		containers = append(containers, sslContainer)
	}
	if gw.Spec.EnableIpsecVpn {
		// config ipsec vpn strongswan pod:
		// port, proto
		// volume: x.509 secret
		// env: proto, port
		// command: ipsec start
		ipsecContainer := corev1.Container{
			Name:  IpsecVpnServer,
			Image: gw.Spec.IpsecVpnImage,
			// mount x.509 secret
			VolumeMounts: []corev1.VolumeMount{
				{
					Name:      gw.Spec.IpsecSecret,
					MountPath: IpsecVpnSecretPath,
					ReadOnly:  true,
				},
			},
			Resources: corev1.ResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
				Limits: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.Cpu),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
			},
			Command: []string{IpsecVpnStartUpCMD},
			Ports: []corev1.ContainerPort{
				{
					ContainerPort: IpSecIsakmpPort,
					Name:          IpSecIsakmpPortKey,
					Protocol:      corev1.Protocol(IpsecProto),
				},
				{
					ContainerPort: IpSecBootPcPort,
					Name:          IpSecBootPcPortKey,
					Protocol:      corev1.Protocol(IpsecProto),
				},
				{
					ContainerPort: IpSecNatPort,
					Name:          IpSecNatPortKey,
					Protocol:      corev1.Protocol(IpsecProto)},
			},
			ImagePullPolicy: corev1.PullIfNotPresent,
			SecurityContext: &corev1.SecurityContext{
				Privileged:               &privileged,
				AllowPrivilegeEscalation: &allowPrivilegeEscalation,
			},
		}
		ipsecSecretVolume := corev1.Volume{
			// define secrect volume
			Name: gw.Spec.IpsecSecret,
			VolumeSource: corev1.VolumeSource{
				Secret: &corev1.SecretVolumeSource{
					SecretName: gw.Spec.IpsecSecret,
					Optional:   &[]bool{true}[0],
				},
			},
		}
		volumes = append(volumes, ipsecSecretVolume)
		containers = append(containers, ipsecContainer)
	}
	containers = append(containers, keepalivedContainer)
	newDs = &appsv1.DaemonSet{
		ObjectMeta: metav1.ObjectMeta{
			Name:      gw.Name,
			Namespace: gw.Namespace,
			Labels:    labels,
		},
		Spec: appsv1.DaemonSetSpec{
			Selector: &metav1.LabelSelector{
				MatchLabels: labels,
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels:      labels,
					Annotations: newPodAnnotations,
				},
				Spec: corev1.PodSpec{
					Containers: containers,
					Volumes:    volumes,
					// host network
					HostNetwork: true,
				},
			},
			UpdateStrategy: appsv1.DaemonSetUpdateStrategy{
				Type: appsv1.RollingUpdateDaemonSetStrategyType,
			},
		},
	}

	if len(gw.Spec.Selector) > 0 {
		selectors := make(map[string]string)
		for _, v := range gw.Spec.Selector {
			parts := strings.Split(strings.TrimSpace(v), ":")
			if len(parts) != 2 {
				continue
			}
			selectors[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
		newDs.Spec.Template.Spec.NodeSelector = selectors
	}

	if len(gw.Spec.Tolerations) > 0 {
		newDs.Spec.Template.Spec.Tolerations = gw.Spec.Tolerations
	}

	if gw.Spec.Affinity.NodeAffinity != nil ||
		gw.Spec.Affinity.PodAffinity != nil ||
		gw.Spec.Affinity.PodAntiAffinity != nil {
		newDs.Spec.Template.Spec.Affinity = &gw.Spec.Affinity
	}

	// set gw instance as the owner and controller
	if err := controllerutil.SetControllerReference(gw, newDs, r.Scheme); err != nil {
		r.Log.Error(err, "failed to set vpn gw as the owner and controller")
		return nil
	}
	return
}

// belonging to the given vpn gw CR name.
func labelsForVpnGw(gw *vpngwv1.VpnGw) map[string]string {
	return map[string]string{
		EnableSslVpnLabel:   strconv.FormatBool(gw.Spec.EnableSslVpn),
		EnableIpsecVpnLabel: strconv.FormatBool(gw.Spec.EnableIpsecVpn),
	}
}

func (r *VpnGwReconciler) handleAddOrUpdateVpnStatefulset(req ctrl.Request, gw *vpngwv1.VpnGw, ka *vpngwv1.KeepAlived) error {
	// create or update statefulset
	needToCreate := false
	oldSts := &appsv1.StatefulSet{}
	err := r.Get(context.Background(), req.NamespacedName, oldSts)
	if err != nil {
		if apierrors.IsNotFound(err) {
			needToCreate = true
		} else {
			r.Log.Error(err, "failed to get old statefulset")
			return err
		}
	}
	newGw := gw.DeepCopy()
	if needToCreate {
		// create statefulset
		newSts := r.statefulSetForVpnGw(gw, ka, nil)
		err = r.Create(context.Background(), newSts)
		if err != nil {
			r.Log.Error(err, "failed to create the new statefulset")
			return err
		}
		time.Sleep(5 * time.Second)
		return nil
	} else if r.isChanged(newGw, nil) {
		// update statefulset
		newSts := r.statefulSetForVpnGw(gw, ka, oldSts.DeepCopy())
		err = r.Update(context.Background(), newSts)
		if err != nil {
			r.Log.Error(err, "failed to update the statefulset")
			return err
		}
		time.Sleep(5 * time.Second)
		return nil
	}
	r.Log.Info("vpn gw statefulset not changed", "vpn gw", gw.Name)
	return nil
}

func (r *VpnGwReconciler) handleAddOrUpdateVpnDaemonset(req ctrl.Request, gw *vpngwv1.VpnGw, ka *vpngwv1.KeepAlived) error {
	// use daemonset to reconcile static pod yaml
	// create or update daemonset
	needToCreate := false
	oldDs := &appsv1.DaemonSet{}
	err := r.Get(context.Background(), req.NamespacedName, oldDs)
	if err != nil {
		if apierrors.IsNotFound(err) {
			needToCreate = true
		} else {
			r.Log.Error(err, "failed to get old daemonset")
			return err
		}
	}
	newGw := gw.DeepCopy()
	if needToCreate {
		// create daemonset
		newSts := r.daemonsetForVpnGw(gw, ka, nil)
		err = r.Create(context.Background(), newSts)
		if err != nil {
			r.Log.Error(err, "failed to create the new daemonset")
			return err
		}
		time.Sleep(5 * time.Second)
		return nil
	} else if r.isChanged(newGw, nil) {
		// update daemonset
		newSts := r.daemonsetForVpnGw(gw, ka, oldDs.DeepCopy())
		err = r.Update(context.Background(), newSts)
		if err != nil {
			r.Log.Error(err, "failed to update the daemonset")
			return err
		}
		time.Sleep(5 * time.Second)
		return nil
	}
	r.Log.Info("vpn gw daemonset not changed", "vpn gw", gw.Name)
	return nil
}
func (r *VpnGwReconciler) handleAddOrUpdateVpnGw(ctx context.Context, req ctrl.Request) (SyncState, error) {
	// create vpn gw statefulset
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start handleAddOrUpdateVpnGw", "vpn gw", namespacedName)
	defer r.Log.Info("end handleAddOrUpdateVpnGw", "vpn gw", namespacedName)

	// fetch vpn gw
	gw, err := r.getVpnGw(ctx, req.NamespacedName)
	if err != nil {
		err = fmt.Errorf("failed to get vpn gw: %v", err)
		r.Log.Error(err, "failed to get vpn gw")
		return SyncStateErrorNoRetry, err
	}
	if gw == nil {
		// vpn gw deleted
		return SyncStateSuccess, nil
	}
	if err := r.validateVpnGw(gw); err != nil {
		r.Log.Error(err, "failed to validate vpn gw")
		// invalid spec no retry
		return SyncStateErrorNoRetry, err
	}

	ka := &vpngwv1.KeepAlived{
		ObjectMeta: metav1.ObjectMeta{
			Name:      gw.Spec.Keepalived,
			Namespace: gw.Namespace,
		},
	}

	ka, err = r.getValidKeepalived(ctx, ka)
	if err != nil {
		err = fmt.Errorf("failed to get keepalived: %v", err)
		r.Log.Error(err, "failed to get keepalived")
		return SyncStateError, err
	}
	if err := r.validateKeepalived(ka); err != nil {
		r.Log.Error(err, "failed to validate keepalived")
		// invalid spec no retry
		return SyncStateErrorNoRetry, err
	}

	// create vpn gw or update
	if gw.Spec.WorkloadType == "statefulset" {
		if err := r.handleAddOrUpdateVpnStatefulset(req, gw, ka); err != nil {
			r.Log.Error(err, "failed to handleAddOrUpdateVpnStatefulset")
			return SyncStateError, err
		}
	} else {
		if err := r.handleAddOrUpdateVpnDaemonset(req, gw, ka); err != nil {
			r.Log.Error(err, "failed to handleAddOrUpdateVpnDaemonset")
			return SyncStateError, err
		}
	}

	var conns []string
	if gw.Spec.EnableIpsecVpn {
		// fetch ipsec connections
		res, err := r.getIpsecConnections(context.Background(), gw)
		if err != nil {
			r.Log.Error(err, "failed to list vpn gw ipsec connections")
			return SyncStateError, err
		}
		// format ipsec connections
		connections := ""
		for _, v := range *res {
			if v.Spec.VpnGw == "" || v.Spec.VpnGw != gw.Name {
				err := fmt.Errorf("ipsec connection spec vpn gw is invalid, spec vpn gw: %s", v.Spec.VpnGw)
				r.Log.Error(err, "ignore invalid ipsec connection")
				continue
			}
			if v.Spec.Auth == "" || v.Spec.IkeVersion == "" || v.Spec.Proposals == "" ||
				v.Spec.LocalCN == "" || v.Spec.LocalPublicIp == "" || v.Spec.LocalPrivateCidrs == "" ||
				v.Spec.RemoteCN == "" || v.Spec.RemotePublicIp == "" || v.Spec.RemotePrivateCidrs == "" {
				err := fmt.Errorf("invalid ipsec connection, exist empty spec: %+v", v)
				r.Log.Error(err, "ignore invalid ipsec connection")
			}
			connections += fmt.Sprintf("%s %s %s %s %s %s %s %s %s %s,", v.Name, v.Spec.Auth, v.Spec.IkeVersion, v.Spec.Proposals,
				v.Spec.LocalCN, v.Spec.LocalPublicIp, v.Spec.LocalPrivateCidrs,
				v.Spec.RemoteCN, v.Spec.RemotePublicIp, v.Spec.RemotePrivateCidrs)
		}
		if connections != "" {
			// get pod from statefulset
			pod := &corev1.Pod{}
			err = r.Get(context.Background(), types.NamespacedName{
				Name:      gw.Name + "-0",
				Namespace: gw.Namespace,
			}, pod)

			if err != nil {
				r.Log.Error(err, "failed to get vpn gw pod")
				time.Sleep(1 * time.Second)
				return SyncStateError, err
			} else if pod.Status.Phase != "Running" {
				err = fmt.Errorf("pod is not running now")
				r.Log.Error(err, "wait a while to refresh vpn gw ipsec connections")
				time.Sleep(5 * time.Second)
				return SyncStateError, err
			}
			r.Log.Info("found vpn gw pod", "pod", pod.Name)
			// exec pod to run cmd to refresh ipsec connections
			cmd := fmt.Sprintf(IpsecConnectionRefreshTemplate, connections)
			r.Log.Info("start run cmd", "cmd", cmd)
			// refresh ipsec connections by exec pod
			stdOutput, errOutput, err := ExecuteCommandInContainer(r.KubeClient, r.RestConfig, pod.Namespace, pod.Name, IpsecVpnServer, []string{"/bin/bash", "-c", cmd}...)
			if err != nil {
				if len(errOutput) > 0 {
					err = fmt.Errorf("failed to ExecuteCommandInContainer, errOutput: %v", errOutput)
					r.Log.Error(err, "failed to refresh vpn gw ipsec connections")
				}
				if len(stdOutput) > 0 {
					err = fmt.Errorf("failed to ExecuteCommandInContainer, errOutput: %v", errOutput)
					r.Log.Error(err, "failed to refresh vpn gw ipsec connections")
				}
				time.Sleep(2 * time.Second)
				return SyncStateError, err
			}
			for _, conn := range *res {
				conns = append(conns, conn.Name)
			}
		}
	}
	newGw := gw.DeepCopy()
	if r.isChanged(newGw, conns) {
		err = r.Status().Update(context.Background(), newGw)
		if err != nil {
			r.Log.Error(err, "failed to update vpn gw status")
			return SyncStateError, err
		}
	}
	return SyncStateSuccess, nil
}

func (r *VpnGwReconciler) getVpnGw(ctx context.Context, name types.NamespacedName) (*vpngwv1.VpnGw, error) {
	var res vpngwv1.VpnGw
	err := r.Get(ctx, name, &res)
	if apierrors.IsNotFound(err) { // in case of delete, get fails and we need to pass nil to the handler
		return nil, nil
	}
	if err != nil {
		err = fmt.Errorf("failed to get vpn gw: %v", err)
		r.Log.Error(err, "failed to get vpn gw")
		return nil, err
	}
	return &res, nil
}

// returns all ipsec connections who has labels about the vpn gw
func (r *VpnGwReconciler) getIpsecConnections(ctx context.Context, gw *vpngwv1.VpnGw) (*[]vpngwv1.IpsecConn, error) {
	var res vpngwv1.IpsecConnList
	err := r.List(ctx, &res, client.MatchingLabels{VpnGwLabel: gw.Name})
	if err != nil {
		err = fmt.Errorf("failed to list vpn gw ipsec connections: %v", err)
		r.Log.Error(err, "failed to list vpn gw ipsec connections")
		return nil, err
	}
	return &res.Items, nil
}

func (r *VpnGwReconciler) getValidKeepalived(ctx context.Context, ka *vpngwv1.KeepAlived) (*vpngwv1.KeepAlived, error) {
	var res vpngwv1.KeepAlived
	name := types.NamespacedName{
		Name:      ka.Name,
		Namespace: ka.Namespace,
	}

	err := r.Get(ctx, name, &res)
	if err != nil {
		err := fmt.Errorf("failed to get keepalived %s: %w", name.String(), err)
		r.Log.Error(err, "failed to get keepalived")
		return nil, err
	}

	return &res, nil
}
