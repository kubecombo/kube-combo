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
	VpnGwLabel = "vpn-gw"

	// ssl vpn openvpn
	SslVpnServer = "ssl-vpn"

	// statefulset ssl vpn pod start up command
	SslVpnStsCMD = "/etc/openvpn/setup/configure.sh"

	// daemonset ssl vpn pod start up command
	SslVpnDsCMD = "/etc/openvpn/setup/daemonset-start.sh"

	// cache path from ds openvpn to k8s static pod openvpn
	SslVpnHostCachePath = "/etc/host-init-openvpn"
	SslVpnCacheName     = "openvpn-cache"

	// ds pod use this volume to copy static pod yaml to kubelet
	k8sManifests = "k8s-manifests"

	EnableSslVpnLabel = "enable-ssl-vpn"

	k8sManifestsPathKey = "K8S_MANIFESTS_PATH"

	// vpn gw pod env
	SslVpnProtoKey      = "SSL_VPN_PROTO"
	SslVpnPortKey       = "SSL_VPN_PORT"
	SslVpnCipherKey     = "SSL_VPN_CIPHER"
	SslVpnAuthKey       = "SSL_VPN_AUTH"
	SslVpnSubnetCidrKey = "SSL_VPN_SUBNET_CIDR"
	SslVpnImageKey      = "SSL_VPN_IMAGE"

	// ipsec vpn strongswan
	IPSecVpnServer = "ipsec-vpn"

	IPSecVpnLocalPortKey  = "ipsec-local"
	IPSecVpnRemotePortKey = "ipsec-remote"

	// statefulset ipsec vpn pod start up command
	IPSecVpnStsCMD = "/usr/sbin/charon-systemd"

	IPSecRefreshConnectionX509Template = "/connection.sh refresh-x509 %s"
	IPSecRefreshConnectionPSKTemplate  = "/connection.sh refresh-psk %s"

	// cache path from ds ipsec vpn to k8s static pod ipsecvpn
	IPSecVpnHostCachePath = "/etc/host-init-strongswan"
	IPSecVpnCacheName     = "strongswan-cache"

	EnableIPSecVpnLabel = "enable-ipsec-vpn"

	IPSecBootPcPortKey = "bootpc"
	IPSecIsakmpPortKey = "isakmp"
	IPSecNatPortKey    = "nat"

	IPSecProto = "UDP"

	IPSecVpnImageKey = "IPSEC_VPN_IMAGE"
	// IPSecRemoteAddrsKey = "IPSEC_REMOTE_ADDRS"
	// IPSecRemoteTsKey    = "IPSEC_REMOTE_TS"
)

// keepalived
const (
	KeepalivedVipKey          = "KEEPALIVED_VIP"
	KeepalivedVirtualRouterID = "KEEPALIVED_VIRTUAL_ROUTER_ID"
	keepalivedNicKey          = "KEEPALIVED_NIC"
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

	// vpn in ds need mount k8s manifests path to copy static pod yaml to
	K8sManifestsPath string

	// ssl vpn openvpn
	SslVpnTCP string
	SslVpnUDP string
	// ssl vpn mount path
	SslVpnSecretPath string
	DhSecretPath     string

	// ipsec vpn strongswan
	IPSecBootPcPort string
	IPSecIsakmpPort string
	IPSecNatPort    string
	// ipsec vpn mount path
	IPSecVpnSecretPath string
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
		For(&myv1.VpnGw{},
			builder.WithPredicates(
				predicate.NewPredicateFuncs(
					func(object client.Object) bool {
						_, ok := object.(*myv1.VpnGw)
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
		Owns(&myv1.IpsecConn{}).
		Owns(&myv1.KeepAlived{}).
		Complete(r)
}

func (r *VpnGwReconciler) validateKeepalived(ka *myv1.KeepAlived) error {
	if ka.Spec.Image == "" {
		err := errors.New("keepalived image is required")
		r.Log.Error(err, "should set keepalived image")
		return err
	}
	if ka.Spec.VipV4 == "" && ka.Spec.VipV6 == "" {
		err := errors.New("keepalived vip v4 or v6 ip is required")
		r.Log.Error(err, "should set keepalived vip")
		return err
	}
	return nil
}

func (r *VpnGwReconciler) validateVpnGw(gw *myv1.VpnGw) error {
	r.Log.V(3).Info("start validateVpnGw", "vpn gw", gw)
	if gw.Spec.CPU == "" || gw.Spec.Memory == "" {
		err := errors.New("vpn gw cpu and memory is required")
		r.Log.Error(err, "should set cpu and memory")
		return err
	}

	if !gw.Spec.EnableSslVpn && !gw.Spec.EnableIPSecVpn {
		err := errors.New("vpn gw spec should enable ssl vpn or ipsec vpn at least one")
		r.Log.Error(err, "vpn gw spec should enable ssl vpn or ipsec vpn at least one")
		return err
	}

	if gw.Spec.EnableSslVpn {
		if gw.Spec.SslVpnSecret == "" {
			err := errors.New("ssl vpn secret is required")
			r.Log.Error(err, "should set ssl vpn secret")
			return err
		}
		if gw.Spec.DhSecret == "" {
			err := errors.New("ssl vpn dh secret is required")
			r.Log.Error(err, "should set ssl vpn dh secret")
			return err
		}
		if gw.Spec.SslVpnCipher == "" {
			err := errors.New("ssl vpn cipher is required")
			r.Log.Error(err, "should set cipher")
			return err
		}
		if gw.Spec.SslVpnProto == "" {
			err := errors.New("ssl vpn proto is required")
			r.Log.Error(err, "should set ssl vpn proto")
			return err
		}
		if gw.Spec.SslVpnSubnetCidr == "" {
			err := errors.New("ssl vpn subnet cidr is required")
			r.Log.Error(err, "should set ssl vpn client and server subnet")
			return err
		}
		if gw.Spec.SslVpnProto != "udp" && gw.Spec.SslVpnProto != "tcp" {
			err := errors.New("ssl vpn proto should be udp or tcp")
			r.Log.Error(err, "should set reasonable vpn proto")
			return err
		}
		if gw.Spec.SslVpnImage == "" {
			err := errors.New("ssl vpn image is required")
			r.Log.Error(err, "should set ssl vpn image")
			return err
		}
	}

	if gw.Spec.EnableIPSecVpn {
		if gw.Spec.IPSecVpnImage == "" {
			err := errors.New("ipsec vpn image is required")
			r.Log.Error(err, "should set ipsec vpn image")
			return err
		}
	}
	return nil
}

func (r *VpnGwReconciler) isChanged(gw *myv1.VpnGw, ipsecConnections []string) bool {
	if gw.Status.Keepalived == "" && gw.Spec.Keepalived != "" {
		return true
	}
	if gw.Status.CPU != gw.Spec.CPU {
		return true
	}
	if gw.Status.Memory != gw.Spec.Memory {
		return true
	}
	if gw.Status.QoSBandwidth != gw.Spec.QoSBandwidth {
		return true
	}
	if gw.Status.Replicas != gw.Spec.Replicas {
		return true
	}
	if gw.Status.EnableSslVpn != gw.Spec.EnableSslVpn {
		return true
	}
	if gw.Status.SslVpnCipher != gw.Spec.SslVpnCipher {
		return true
	}
	if gw.Status.SslVpnProto != gw.Spec.SslVpnProto {
		return true
	}
	if gw.Status.SslVpnSubnetCidr != gw.Spec.SslVpnSubnetCidr {
		return true
	}
	if gw.Status.SslVpnImage != gw.Spec.SslVpnImage {
		return true
	}
	if gw.Status.EnableIPSecVpn != gw.Spec.EnableIPSecVpn {
		return true
	}
	if gw.Status.IPSecVpnImage != gw.Spec.IPSecVpnImage {
		return true
	}
	if gw.Status.EnableIPSecVpn && ipsecConnections != nil {
		return true
	}
	if !reflect.DeepEqual(gw.Spec.IPSecConnections, ipsecConnections) {
		return true
	}
	if !reflect.DeepEqual(gw.Spec.Selector, gw.Status.Selector) {
		return true
	}
	if !reflect.DeepEqual(gw.Spec.Tolerations, gw.Status.Tolerations) {
		return true
	}
	if !reflect.DeepEqual(gw.Spec.Affinity, gw.Status.Affinity) {
		return true
	}
	return false
}

func (r *VpnGwReconciler) UpdateVpnGW(ctx context.Context, req ctrl.Request, ipsecConnections []string) error {
	// fetch vpn gw
	gw, err := r.getVpnGw(ctx, req.NamespacedName)
	if err != nil {
		r.Log.Error(err, "failed to get vpn gw")
		return err
	}
	if gw == nil {
		// vpn gw deleted
		return nil
	}
	changed := false
	newGw := gw.DeepCopy()
	if gw.Status.Keepalived == "" && gw.Spec.Keepalived != "" {
		newGw.Status.Keepalived = gw.Spec.Keepalived
		changed = true
	}
	if gw.Status.CPU != gw.Spec.CPU {
		newGw.Status.CPU = gw.Spec.CPU
		changed = true
	}
	if gw.Status.Memory != gw.Spec.Memory {
		newGw.Status.Memory = gw.Spec.Memory
		changed = true
	}
	if gw.Status.QoSBandwidth != gw.Spec.QoSBandwidth {
		newGw.Status.QoSBandwidth = gw.Spec.QoSBandwidth
		changed = true
	}
	if gw.Status.Replicas != gw.Spec.Replicas {
		newGw.Status.Replicas = gw.Spec.Replicas
		changed = true
	}

	if gw.Status.EnableSslVpn != gw.Spec.EnableSslVpn {
		newGw.Status.EnableSslVpn = gw.Spec.EnableSslVpn
		if gw.Status.SslVpnCipher != gw.Spec.SslVpnCipher {
			newGw.Status.SslVpnCipher = gw.Spec.SslVpnCipher
		}
		if gw.Status.SslVpnProto != gw.Spec.SslVpnProto {
			newGw.Status.SslVpnProto = gw.Spec.SslVpnProto
		}
		if gw.Status.SslVpnSubnetCidr != gw.Spec.SslVpnSubnetCidr {
			newGw.Status.SslVpnSubnetCidr = gw.Spec.SslVpnSubnetCidr
		}
		if gw.Status.SslVpnImage != gw.Spec.SslVpnImage {
			newGw.Status.SslVpnImage = gw.Spec.SslVpnImage
		}
		changed = true
	}

	if gw.Status.EnableIPSecVpn != gw.Spec.EnableIPSecVpn {
		newGw.Status.EnableIPSecVpn = gw.Spec.EnableIPSecVpn
		if gw.Status.IPSecVpnImage != gw.Spec.IPSecVpnImage {
			newGw.Status.IPSecVpnImage = gw.Spec.IPSecVpnImage
		}
		changed = true
	}

	if gw.Status.EnableIPSecVpn && ipsecConnections != nil {
		if !reflect.DeepEqual(gw.Spec.IPSecConnections, ipsecConnections) {
			newGw.Spec.IPSecConnections = ipsecConnections
			newGw.Status.IPSecConnections = ipsecConnections
			changed = true
		}
	}

	if !reflect.DeepEqual(gw.Spec.Selector, gw.Status.Selector) {
		newGw.Status.Selector = gw.Spec.Selector
		changed = true
	}
	if !reflect.DeepEqual(gw.Spec.Tolerations, gw.Status.Tolerations) {
		newGw.Status.Tolerations = gw.Spec.Tolerations
		changed = true
	}
	if !reflect.DeepEqual(gw.Spec.Affinity, gw.Status.Affinity) {
		newGw.Status.Affinity = gw.Spec.Affinity
		changed = true
	}

	if !changed {
		return nil
	}
	if err := r.Status().Update(context.Background(), newGw); err != nil {
		r.Log.Error(err, "failed to update vpn gw status")
		return err
	}
	return nil
}

func (r *VpnGwReconciler) statefulSetForVpnGw(gw *myv1.VpnGw, ka *myv1.KeepAlived, oldSts *appsv1.StatefulSet) (newSts *appsv1.StatefulSet) {
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
			Limits: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(gw.Spec.CPU),
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
				Name:  KeepalivedVirtualRouterID,
				Value: strconv.Itoa(ka.Status.RouterID),
			},
			{
				Name:  keepalivedNicKey,
				Value: ka.Spec.Nic,
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
		cmd := []string{SslVpnStsCMD}
		sslVpnPort := r.SslVpnUDP
		if gw.Spec.SslVpnProto == "tcp" {
			sslVpnPort = r.SslVpnTCP
		}
		// turn ssl vpn port into int32
		sslVpnPortInt32, err := getPortInt32(sslVpnPort)
		if err != nil {
			r.Log.Error(err, "failed to convert ssl vpn port to int32")
			return nil
		}
		sslContainer := corev1.Container{
			Name:  SslVpnServer,
			Image: gw.Spec.SslVpnImage,
			VolumeMounts: []corev1.VolumeMount{
				// mount x.509 secret
				{
					Name:      gw.Spec.SslVpnSecret,
					MountPath: r.SslVpnSecretPath,
					ReadOnly:  true,
				},
				// mount openssl dhparams secret
				{
					Name:      gw.Spec.DhSecret,
					MountPath: r.DhSecretPath,
					ReadOnly:  true,
				},
			},
			Resources: corev1.ResourceRequirements{
				Limits: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.CPU),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
			},
			Command: cmd,
			Ports: []corev1.ContainerPort{{
				ContainerPort: sslVpnPortInt32,
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
					Value: sslVpnPort,
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
				{
					Name:  k8sManifestsPathKey,
					Value: r.K8sManifestsPath,
				},
				{
					Name:  SslVpnImageKey,
					Value: gw.Spec.SslVpnImage,
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
	if gw.Spec.EnableIPSecVpn {
		// config ipsec vpn strongswan pod:
		// port, proto
		// volume: x.509 secret
		// env: proto, port
		// command: ipsec start
		cmd := []string{IPSecVpnStsCMD}
		IPSecIsakmpPortInt32, err := getPortInt32(r.IPSecIsakmpPort)
		if err != nil {
			r.Log.Error(err, "failed to convert ipsec isakmp port to int32")
			return nil
		}
		IPSecNatPortInt32, err := getPortInt32(r.IPSecNatPort)
		if err != nil {
			r.Log.Error(err, "failed to convert ipsec nat port to int32")
			return nil
		}
		ipsecContainer := corev1.Container{
			Name:  IPSecVpnServer,
			Image: gw.Spec.IPSecVpnImage,
			Resources: corev1.ResourceRequirements{
				Limits: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.CPU),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
			},
			Command: cmd,
			Ports: []corev1.ContainerPort{
				{
					ContainerPort: IPSecIsakmpPortInt32,
					Name:          IPSecIsakmpPortKey,
					Protocol:      corev1.Protocol(IPSecProto),
				},
				{
					ContainerPort: IPSecNatPortInt32,
					Name:          IPSecNatPortKey,
					Protocol:      corev1.Protocol(IPSecProto),
				},
			},
			Env: []corev1.EnvVar{
				{
					Name:  k8sManifestsPathKey,
					Value: r.K8sManifestsPath,
				},
				{
					Name:  IPSecVpnImageKey,
					Value: gw.Spec.IPSecVpnImage,
				},
			},
			ImagePullPolicy: corev1.PullIfNotPresent,
			SecurityContext: &corev1.SecurityContext{
				Privileged:               &privileged,
				AllowPrivilegeEscalation: &allowPrivilegeEscalation,
			},
		}
		if !gw.Spec.IPSecEnablePSK {
			// psk or x.509 secret
			ipsecSecretVolumeMount := corev1.VolumeMount{
				Name:      gw.Spec.IPSecSecret,
				MountPath: r.IPSecVpnSecretPath,
				ReadOnly:  true,
			}
			ipsecContainer.VolumeMounts = append(ipsecContainer.VolumeMounts, ipsecSecretVolumeMount)
			ipsecSecretVolume := corev1.Volume{
				// define secrect volume
				Name: gw.Spec.IPSecSecret,
				VolumeSource: corev1.VolumeSource{
					Secret: &corev1.SecretVolumeSource{
						SecretName: gw.Spec.IPSecSecret,
						Optional:   &[]bool{true}[0],
					},
				},
			}
			volumes = append(volumes, ipsecSecretVolume)
		}
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

func (r *VpnGwReconciler) daemonsetForVpnGw(gw *myv1.VpnGw, ka *myv1.KeepAlived, oldDs *appsv1.DaemonSet) (newDs *appsv1.DaemonSet) {
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
	subnet := ""
	v4Vip := ""
	if ka != nil {
		subnet = ka.Spec.Subnet
		v4Vip = ka.Spec.VipV4
	}
	podAnnotations := map[string]string{
		KubeovnLogicalSwitchAnnotation: subnet,
		KubeovnIngressRateAnnotation:   gw.Spec.QoSBandwidth,
		KubeovnEgressRateAnnotation:    gw.Spec.QoSBandwidth,
	}
	for key, value := range podAnnotations {
		newPodAnnotations[key] = value
	}

	containers := []corev1.Container{}
	volumes := []corev1.Volume{}
	if gw.Spec.EnableSslVpn {
		// config ssl vpn openvpn pod:
		// port, proto, cipher, auth, subnet
		// volume: x.509 secret, dhparams secret
		// env: proto, port, cipher, auth, subnet
		// command: openvpn --config /etc/openvpn/server.conf

		cmd := []string{SslVpnDsCMD}
		sslVpnPort := r.SslVpnUDP
		if gw.Spec.SslVpnProto == "tcp" {
			sslVpnPort = r.SslVpnTCP
		}
		// turn ssl vpn port into int32
		sslVpnPortInt32, err := getPortInt32(sslVpnPort)
		if err != nil {
			r.Log.Error(err, "failed to convert ssl vpn port to int32")
			return nil
		}
		sslContainer := corev1.Container{
			Name:  SslVpnServer,
			Image: gw.Spec.SslVpnImage,
			VolumeMounts: []corev1.VolumeMount{
				// use k8s manifests to copy static pod yaml to host kubelet
				{
					Name:      k8sManifests,
					MountPath: r.K8sManifestsPath,
					ReadOnly:  false,
				},
				// use hostpath to copy /etc/openvpn to host
				{
					Name:      SslVpnCacheName,
					MountPath: SslVpnHostCachePath,
					ReadOnly:  false,
				},
				// mount x.509 secret
				{
					Name:      gw.Spec.SslVpnSecret,
					MountPath: r.SslVpnSecretPath,
					ReadOnly:  true,
				},
				// mount openssl dhparams secret
				{
					Name:      gw.Spec.DhSecret,
					MountPath: r.DhSecretPath,
					ReadOnly:  true,
				},
			},
			Resources: corev1.ResourceRequirements{
				Limits: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.CPU),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
			},
			Command: cmd,
			Ports: []corev1.ContainerPort{{
				ContainerPort: sslVpnPortInt32,
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
					Value: sslVpnPort,
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
					Value: v4Vip,
				},
				{
					Name:  k8sManifestsPathKey,
					Value: r.K8sManifestsPath,
				},
				{
					Name:  SslVpnImageKey,
					Value: gw.Spec.SslVpnImage,
				},
			},
			ImagePullPolicy: corev1.PullIfNotPresent,
			SecurityContext: &corev1.SecurityContext{
				Privileged:               &privileged,
				AllowPrivilegeEscalation: &allowPrivilegeEscalation,
			},
		}
		sslConfHostVolume := corev1.Volume{
			Name: SslVpnCacheName,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: SslVpnHostCachePath,
					// if the directory is not exist, create it
					Type: &[]corev1.HostPathType{corev1.HostPathDirectoryOrCreate}[0],
				},
			},
		}
		volumes = append(volumes, sslConfHostVolume)
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
	if gw.Spec.EnableIPSecVpn {
		// config ipsec vpn strongswan pod:
		// port, proto
		// volume: x.509 secret
		// env: proto, port
		// command: ipsec start
		// ipsec vpn use sleep infinity to keep container running
		cmd := []string{"sleep", "infinity"}
		IPSecIsakmpPortInt32, err := getPortInt32(r.IPSecIsakmpPort)
		if err != nil {
			r.Log.Error(err, "failed to convert ipsec isakmp port to int32")
			return nil
		}
		IPSecNatPortInt32, err := getPortInt32(r.IPSecNatPort)
		if err != nil {
			r.Log.Error(err, "failed to convert ipsec nat port to int32")
			return nil
		}

		ipsecContainer := corev1.Container{
			Name:  IPSecVpnServer,
			Image: gw.Spec.IPSecVpnImage,
			// mount x.509 secret
			VolumeMounts: []corev1.VolumeMount{
				// use k8s manifests to copy static pod yaml to host kubelet
				{
					Name:      k8sManifests,
					MountPath: r.K8sManifestsPath,
					ReadOnly:  false,
				},
				// use hostpath to map /etc/swanctl to host
				{
					Name:      IPSecVpnCacheName,
					MountPath: IPSecVpnHostCachePath,
					ReadOnly:  false,
				},
			},
			Resources: corev1.ResourceRequirements{
				Limits: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.CPU),
					corev1.ResourceMemory: resource.MustParse(gw.Spec.Memory),
				},
			},
			Command: cmd,
			Ports: []corev1.ContainerPort{
				{
					ContainerPort: IPSecIsakmpPortInt32,
					Name:          IPSecIsakmpPortKey,
					Protocol:      corev1.Protocol(IPSecProto),
				},
				{
					ContainerPort: IPSecNatPortInt32,
					Name:          IPSecNatPortKey,
					Protocol:      corev1.Protocol(IPSecProto),
				},
			},
			Env: []corev1.EnvVar{
				{
					Name:  k8sManifestsPathKey,
					Value: r.K8sManifestsPath,
				},
				{
					Name:  IPSecVpnImageKey,
					Value: gw.Spec.IPSecVpnImage,
				},
			},
			ImagePullPolicy: corev1.PullIfNotPresent,
			SecurityContext: &corev1.SecurityContext{
				Privileged:               &privileged,
				AllowPrivilegeEscalation: &allowPrivilegeEscalation,
			},
		}
		ipsecConfHostVolume := corev1.Volume{
			Name: IPSecVpnCacheName,
			VolumeSource: corev1.VolumeSource{
				HostPath: &corev1.HostPathVolumeSource{
					Path: IPSecVpnHostCachePath,
					// if the directory is not exist, create it
					Type: &[]corev1.HostPathType{corev1.HostPathDirectoryOrCreate}[0],
				},
			},
		}
		volumes = append(volumes, ipsecConfHostVolume)
		if !gw.Spec.IPSecEnablePSK {
			// psk or x.509 secret
			ipsecSecretVolumeMount := corev1.VolumeMount{
				Name:      gw.Spec.IPSecSecret,
				MountPath: r.IPSecVpnSecretPath,
				ReadOnly:  true,
			}
			ipsecContainer.VolumeMounts = append(ipsecContainer.VolumeMounts, ipsecSecretVolumeMount)
			ipsecSecretVolume := corev1.Volume{
				// define secrect volume
				Name: gw.Spec.IPSecSecret,
				VolumeSource: corev1.VolumeSource{
					Secret: &corev1.SecretVolumeSource{
						SecretName: gw.Spec.IPSecSecret,
						Optional:   &[]bool{true}[0],
					},
				},
			}
			volumes = append(volumes, ipsecSecretVolume)
		}
		containers = append(containers, ipsecContainer)
	}
	k8sManifestsVolume := corev1.Volume{
		Name: k8sManifests,
		VolumeSource: corev1.VolumeSource{
			HostPath: &corev1.HostPathVolumeSource{
				Path: r.K8sManifestsPath,
				// the directory on host must be exist
				Type: &[]corev1.HostPathType{corev1.HostPathDirectory}[0],
			},
		},
	}
	volumes = append(volumes, k8sManifestsVolume)
	// need keepalived
	if ka != nil {
		keepalivedContainer := corev1.Container{
			Name:  KeepAlivedServer,
			Image: ka.Spec.Image,
			Resources: corev1.ResourceRequirements{
				Limits: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(gw.Spec.CPU),
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
					Name:  KeepalivedVirtualRouterID,
					Value: strconv.Itoa(ka.Status.RouterID),
				},
				{
					Name:  keepalivedNicKey,
					Value: ka.Spec.Nic,
				},
			},
			ImagePullPolicy: corev1.PullIfNotPresent,
			SecurityContext: &corev1.SecurityContext{
				Privileged:               &privileged,
				AllowPrivilegeEscalation: &allowPrivilegeEscalation,
			},
		}
		containers = append(containers, keepalivedContainer)
	}
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
func labelsForVpnGw(gw *myv1.VpnGw) map[string]string {
	return map[string]string{
		EnableSslVpnLabel:   strconv.FormatBool(gw.Spec.EnableSslVpn),
		EnableIPSecVpnLabel: strconv.FormatBool(gw.Spec.EnableIPSecVpn),
		VpnGwLabel:          gw.Name,
	}
}

func (r *VpnGwReconciler) handleAddOrUpdateVpnStatefulset(req ctrl.Request, gw *myv1.VpnGw, ka *myv1.KeepAlived) error {
	// create or update statefulset
	needToCreate := false
	oldSts := &appsv1.StatefulSet{}
	err := r.Get(context.Background(), req.NamespacedName, oldSts)
	if err != nil {
		if apierrors.IsNotFound(err) {
			needToCreate = true
		} else {
			r.Log.Error(err, "failed to get statefulset")
			return err
		}
	}
	newGw := gw.DeepCopy()
	// create
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
	}
	// update
	if r.isChanged(newGw, nil) {
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
	// no change
	r.Log.Info("vpn gw statefulset not changed", "vpn gw", gw.Name)
	return nil
}

func (r *VpnGwReconciler) handleAddOrUpdateVpnDaemonset(req ctrl.Request, gw *myv1.VpnGw, ka *myv1.KeepAlived) error {
	// use daemonset to reconcile static pod yaml
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
	newGw := gw.DeepCopy()
	// create daemonset
	if needToCreate {
		newSts := r.daemonsetForVpnGw(gw, ka, nil)
		err = r.Create(context.Background(), newSts)
		if err != nil {
			r.Log.Error(err, "failed to create the new daemonset")
			return err
		}
		time.Sleep(5 * time.Second)
		return nil
	}
	// update daemonset
	if r.isChanged(newGw, nil) {
		newSts := r.daemonsetForVpnGw(gw, ka, oldDs.DeepCopy())
		err = r.Update(context.Background(), newSts)
		if err != nil {
			r.Log.Error(err, "failed to update the daemonset")
			return err
		}
		time.Sleep(5 * time.Second)
		return nil
	}
	// no change
	r.Log.Info("vpn gw daemonset not changed", "vpn gw", gw.Name)
	return nil
}

func (r *VpnGwReconciler) validateIPSecConns(gw *myv1.VpnGw, conns *[]myv1.IpsecConn) (string, SyncState, error) {
	if gw.Spec.IPSecEnablePSK && gw.Spec.DefaultPSK == "" {
		err := fmt.Errorf("vpn gw %s should have one default psk", gw.Name)
		r.Log.Error(err, "invalid ipsec connection")
		return "", SyncStateError, err
	}
	connections := ""
	for _, con := range *conns {
		if gw.Spec.IPSecEnablePSK {
			if con.Spec.ESPProposals == "" {
				err := fmt.Errorf("vpn gw %s ipsec connection should have esp proposals", gw.Name)
				r.Log.Error(err, "invalid ipsec connection")
				return "", SyncStateError, err
			}
			if con.Spec.IKEProposals == "" {
				err := fmt.Errorf("vpn gw %s ipsec connection should have ike proposals", gw.Name)
				r.Log.Error(err, "invalid ipsec connection")
				return "", SyncStateError, err
			}
		}
		if con.Spec.VpnGw == "" || con.Spec.VpnGw != gw.Name {
			err := fmt.Errorf("vpn gw %s ipsec connection %s not belong to vpn gw", gw.Name, con.Name)
			r.Log.Error(err, "ignore invalid ipsec connection")
			return "", SyncStateError, err
		}
		if con.Spec.Auth == "" {
			err := fmt.Errorf("vpn gw %s ipsec connection %s should have auth", gw.Name, con.Name)
			r.Log.Error(err, "invalid ipsec connection")
			return "", SyncStateError, err
		}
		if con.Spec.IkeVersion == "" {
			err := fmt.Errorf("vpn gw %s ipsec connection %s should have ikeVersion", gw.Name, con.Name)
			r.Log.Error(err, "invalid ipsec connection")
			return "", SyncStateError, err
		}
		if con.Spec.IKEProposals == "" {
			err := fmt.Errorf("vpn gw %s ipsec connection %s should have proposals", gw.Name, con.Name)
			r.Log.Error(err, "invalid ipsec connection")
			return "", SyncStateError, err
		}
		if con.Spec.LocalVIP == "" {
			err := fmt.Errorf("vpn gw %s ipsec connection %s should have LocalVIP", gw.Name, con.Name)
			r.Log.Error(err, "invalid ipsec connection")
			return "", SyncStateError, err
		}
		if con.Spec.LocalEIP == "" {
			err := fmt.Errorf("vpn gw %s ipsec connection %s should have localEIP", gw.Name, con.Name)
			r.Log.Error(err, "invalid ipsec connection")
			return "", SyncStateError, err
		}
		if con.Spec.LocalPrivateCidrs == "" {
			err := fmt.Errorf("vpn gw %s ipsec connection %s should have localPrivateCidrs", gw.Name, con.Name)
			r.Log.Error(err, "invalid ipsec connection")
			return "", SyncStateError, err
		}
		if con.Spec.RemoteEIP == "" {
			err := fmt.Errorf("vpn gw %s ipsec connection %s should have remoteEIP", gw.Name, con.Name)
			r.Log.Error(err, "invalid ipsec connection")
			return "", SyncStateError, err
		}
		if con.Spec.RemotePrivateCidrs == "" {
			err := fmt.Errorf("vpn gw %s ipsec connection %s should have remotePrivateCidrs", gw.Name, con.Name)
			r.Log.Error(err, "invalid ipsec connection")
			return "", SyncStateError, err
		}

		if con.Spec.Auth == "pubkey" {
			if con.Spec.RemoteCN == "" || con.Spec.LocalCN == "" {
				err := fmt.Errorf("vpn gw %s ipsec connection %s should have remoteCN, localCN", gw.Name, con.Name)
				r.Log.Error(err, "invalid ipsec connection")
				return "", SyncStateError, err
			}
		}
		// use ":" to split connection
		if con.Spec.Auth == "pubkey" {
			connections += fmt.Sprintf("%s %s %s %s %s %s %s %s %s %s:",
				con.Name, con.Spec.Auth, con.Spec.IkeVersion, con.Spec.IKEProposals,
				con.Spec.LocalCN, con.Spec.LocalEIP, con.Spec.LocalPrivateCidrs,
				con.Spec.RemoteCN, con.Spec.RemoteEIP, con.Spec.RemotePrivateCidrs,
			)
		}
		if con.Spec.Auth == "psk" {
			if gw.Spec.WorkloadType == "static" {
				// host network static pod may use keepalived out of kubecombo
				// should set local vip and gateway
				if con.Spec.LocalGateway == "" && con.Spec.LocalGatewayNic != "" {
					err := fmt.Errorf("vpn gw %s ipsec connection %s should have localVipGateway", gw.Name, con.Name)
					r.Log.Error(err, "invalid ipsec connection")
				}
				if con.Spec.LocalGateway != "" && con.Spec.LocalGatewayNic == "" {
					err := fmt.Errorf("vpn gw %s ipsec connection %s should have localGatewayNic", gw.Name, con.Name)
					r.Log.Error(err, "invalid ipsec connection")
					return "", SyncStateError, err
				}
			}
			connections += fmt.Sprintf("%s %s %s %s %s %s %s %s %s %s %s",
				con.Name, con.Spec.Auth, con.Spec.IkeVersion, con.Spec.IKEProposals,
				con.Spec.LocalVIP, con.Spec.LocalEIP, con.Spec.LocalPrivateCidrs,
				con.Spec.RemoteEIP, con.Spec.RemotePrivateCidrs,
				gw.Spec.DefaultPSK, con.Spec.ESPProposals,
			)
			if con.Spec.LocalGateway != "" && con.Spec.LocalGatewayNic != "" {
				connections += fmt.Sprintf(" %s %s:", con.Spec.LocalGateway, con.Spec.LocalGatewayNic)
			} else {
				connections += ":"
			}
		}
	}
	if connections == "" {
		err := fmt.Errorf("vpn gw %s ipsec connection should have connections", gw.Name)
		r.Log.Error(err, "invalid ipsec connection")
		return "", SyncStateError, err
	}
	return connections, SyncStateSuccess, nil
}

func (r *VpnGwReconciler) handleAddOrUpdateVpnGw(ctx context.Context, req ctrl.Request) (SyncState, error) {
	// create vpn gw statefulset
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start handleAddOrUpdateVpnGw", "vpn gw", namespacedName)
	defer r.Log.Info("end handleAddOrUpdateVpnGw", "vpn gw", namespacedName)

	// fetch vpn gw
	gw, err := r.getVpnGw(ctx, req.NamespacedName)
	if err != nil {
		r.Log.Error(err, "failed to get vpn gw")
		return SyncStateErrorNoRetry, err
	}
	if gw == nil {
		// vpn gw deleted
		return SyncStateSuccess, nil
	}
	if err := r.validateVpnGw(gw); err != nil {
		r.Log.Error(err, "failed to validate vpn gw")
		// invalid spec, no retry
		return SyncStateErrorNoRetry, err
	}
	var ka *myv1.KeepAlived
	if gw.Spec.Keepalived != "" {
		ka = &myv1.KeepAlived{
			ObjectMeta: metav1.ObjectMeta{
				Name:      gw.Spec.Keepalived,
				Namespace: gw.Namespace,
			},
		}
		ka, err = r.getValidKeepalived(ctx, ka)
		if err != nil {
			r.Log.Error(err, "failed to get keepalived")
			return SyncStateError, err
		}
		if err := r.validateKeepalived(ka); err != nil {
			r.Log.Error(err, "failed to validate keepalived")
			// invalid spec no retry
			return SyncStateErrorNoRetry, err
		}
		if ka.Status.RouterID == 0 {
			r.Log.Error(err, "keepalived router id not ready to use, please wait a while")
			time.Sleep(1 * time.Second)
			return SyncStateError, err
		}
	}
	// create vpn gw or update
	// statefulset for vpc case
	// daemonset for static pod case
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
	if gw.Spec.EnableIPSecVpn {
		// refresh ipsec connections
		res, err := r.getIpsecConnections(context.Background(), gw)
		if err != nil {
			r.Log.Error(err, "failed to list vpn gw ipsec connections")
			return SyncStateError, err
		}
		if len(*res) == 0 {
			err := fmt.Errorf("vpn gw %s has no ipsec connections", gw.Name)
			r.Log.Error(err, "no ipsec connections, wait a while to refresh")
			time.Sleep(5 * time.Second)
			return SyncStateError, err
		}

		// format ipsec connections
		connections, state, err := r.validateIPSecConns(gw, res)
		if err != nil {
			r.Log.Error(err, "failed to validate ipsec connections")
			return state, err
		}

		// exec pod to run cmd to refresh ipsec connections
		cmd := fmt.Sprintf(IPSecRefreshConnectionX509Template, connections)
		if gw.Spec.IPSecEnablePSK {
			cmd = fmt.Sprintf(IPSecRefreshConnectionPSKTemplate, connections)
		}
		// get pods
		podNames, podNotRunErr := r.getVpnGwPodNames(context.Background(), req.NamespacedName, gw)
		for _, podName := range podNames {
			r.Log.Info("refresh ipsec connections start", "pod", podName, "cmd", cmd)
			// refresh ipsec connections by exec pod
			stdOutput, errOutput, err := ExecuteCommandInContainer(r.KubeClient, r.RestConfig, gw.Namespace, podName, IPSecVpnServer, []string{"/bin/bash", "-c", cmd}...)
			if err != nil {
				if len(errOutput) > 0 {
					err = fmt.Errorf("failed to ExecuteCommandInContainer, errOutput: %v", errOutput)
					r.Log.Error(err, "failed to refresh vpn gw ipsec connections")
				}
				if len(stdOutput) > 0 {
					err = fmt.Errorf("failed to ExecuteCommandInContainer, errOutput: %v", errOutput)
					r.Log.Error(err, "failed to refresh vpn gw ipsec connections")
				}
				time.Sleep(5 * time.Second)
				return SyncStateError, err
			}
			r.Log.Info("refresh ipsec connections ok", "pod", podName, "output", stdOutput)
		}
		if podNotRunErr != nil {
			r.Log.Error(podNotRunErr, "pod not running now")
			time.Sleep(5 * time.Second)
			return SyncStateError, podNotRunErr
		}
		for _, conn := range *res {
			conns = append(conns, conn.Name)
		}
	}
	if err := r.UpdateVpnGW(ctx, req, conns); err != nil {
		r.Log.Error(err, "failed to update vpn gw")
		return SyncStateError, err
	}
	return SyncStateSuccess, nil
}

func (r *VpnGwReconciler) getVpnGwPodNames(ctx context.Context, name types.NamespacedName, gw *myv1.VpnGw) ([]string, error) {
	enableVPN := EnableSslVpnLabel
	if gw.Spec.EnableIPSecVpn {
		enableVPN = EnableIPSecVpnLabel
	}
	podList := &corev1.PodList{}
	err := r.List(ctx, podList, client.InNamespace(name.Namespace), client.MatchingLabels{enableVPN: "true", VpnGwLabel: gw.Name})
	if err != nil {
		r.Log.Error(err, "failed to list pods", "namespace", name.Namespace)
		return nil, err
	}
	podNames := []string{}
	// check if all pods are running, return running pod names
	badPodNames := []string{}
	for _, pod := range podList.Items {
		if pod.Status.Phase != "Running" {
			err = fmt.Errorf("pod %s is not running now", pod.Name)
			r.Log.Error(err, "wait a while to refresh vpn gw ipsec connections")
			badPodNames = append(badPodNames, pod.Name)
		}
		podNames = append(podNames, pod.Name)
	}
	r.Log.Info("found running vpn gw pod", "pod", podNames)
	if len(podNames) == 0 {
		return nil, fmt.Errorf("gw %s has no running pod", gw.Name)
	}
	if len(badPodNames) > 0 {
		return podNames, fmt.Errorf("pod %v is not running now", badPodNames)
	}
	return podNames, nil
}

func (r *VpnGwReconciler) getVpnGw(ctx context.Context, name types.NamespacedName) (*myv1.VpnGw, error) {
	var res myv1.VpnGw
	err := r.Get(ctx, name, &res)
	if apierrors.IsNotFound(err) { // in case of delete, get fails and we need to pass nil to the handler
		return nil, nil
	}
	if err != nil {
		r.Log.Error(err, "failed to get vpn gw")
		return nil, err
	}
	return &res, nil
}

// returns all ipsec connections who has labels about the vpn gw
func (r *VpnGwReconciler) getIpsecConnections(ctx context.Context, gw *myv1.VpnGw) (*[]myv1.IpsecConn, error) {
	var res myv1.IpsecConnList
	err := r.List(ctx, &res, client.MatchingLabels{VpnGwLabel: gw.Name})
	if err != nil {
		r.Log.Error(err, "failed to list vpn gw ipsec connections")
		return nil, err
	}
	return &res.Items, nil
}

func (r *VpnGwReconciler) getValidKeepalived(ctx context.Context, ka *myv1.KeepAlived) (*myv1.KeepAlived, error) {
	var res myv1.KeepAlived
	name := types.NamespacedName{
		Name:      ka.Name,
		Namespace: ka.Namespace,
	}

	err := r.Get(ctx, name, &res)
	if err != nil {
		r.Log.Error(err, "failed to get keepalived")
		return nil, err
	}

	return &res, nil
}

// getPortInt32 converts a string to an int32 port,
// ensuring the port is within the valid range.
func getPortInt32(portStr string) (int32, error) {
	// 使用 ParseInt 来解析字符串并限制位数
	portInt64, err := strconv.ParseInt(portStr, 10, 32) // 10为基数，32为位数
	if err != nil {
		return 0, errors.New("failed to convert port to int")
	}

	// turn portInt64 into int32
	portInt := int32(portInt64)

	// Check if the port is within valid range for int32
	if portInt < 1 || portInt > 65535 {
		return 0, errors.New("invalid port")
	}

	return portInt, nil
}
