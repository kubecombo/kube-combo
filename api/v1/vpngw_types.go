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

package v1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// VpnGwSpec defines the desired state of VpnGw
type VpnGwSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// cpu, memory request
	// cpu, memory limit
	// 1C 1G at least

	// +kubebuilder:validation:Required
	Cpu string `json:"cpu"`

	// +kubebuilder:validation:Required
	Memory string `json:"memory"`

	// 1Mbps bandwidth at least
	// +kubebuilder:validation:Required
	QoSBandwidth string `json:"qosBandwidth"`

	// vpn gw private vpc subnet static ip

	// statefulset replicas

	// +kubebuilder:validation:Required
	// +kubebuilder:default:=2
	Replicas int32 `json:"replicas"`

	// vpn gw pod node selector
	Selector []string `json:"selector,omitempty"`

	// vpn gw pod tolerations
	Tolerations []corev1.Toleration `json:"tolerations,omitempty"`

	// vpn gw pod affinity
	Affinity corev1.Affinity `json:"affinity,omitempty"`

	// vpn gw enable ssl vpn

	// +kubebuilder:validation:Required
	// +kubebuilder:default:=false
	EnableSslVpn bool `json:"enableSslVpn"`

	// ssl vpn secret name, the secret should in the same namespace as the vpn gw
	SslSecret string `json:"sslSecret,omitempty"`

	// ssl vpn dh secret name, the secret should in the same namespace as the vpn gw
	DhSecret   string `json:"dhSecret,omitempty"`
	OvpnCipher string `json:"ovpnCipher"`

	// ssl vpn use openvpn server
	// all ssl vpn spec start with ovpn
	// ovpn ssl vpn proto, udp or tcp, udp probably is better
	// +kubebuilder:default:=udp
	OvpnProto string `json:"ovpnProto"`
	// ovpn ssl vpn port, default 1194 for udp, 443 for tcp
	// +kubebuilder:default:=1194
	OvpnPort int `json:"ovpnPort"`

	// ovpn ssl vpn clinet server subnet cidr 10.240.0.0/16
	OvpnSubnetCidr string `json:"ovpnSubnetCidr"`

	// ssl vpn server image, use Dockerfile.openvpn
	SslVpnImage string `json:"sslVpnImage"`

	// pod svc cidr 10.96.0.0/20
	// OvpnSvcCidr string `json:"ovpnSslVpnSvcCidr"`

	// vpn gw enable ipsec vpn

	// +kubebuilder:validation:Required
	// +kubebuilder:default:=false
	EnableIpsecVpn bool `json:"enableIpsecVpn"`

	// ipsec use strongswan server
	// all ipsec vpn spec start with ipsec
	// ipsec vpn secret name, the secret should in the same namespace as the vpn gw
	IpsecSecret string `json:"ipsecSecret,omitempty"`

	// ipsec vpn local and remote connections, inlude remote ip and subnet
	IpsecConnections []string `json:"ipsecConnections,omitempty"`

	// ipsec vpn server image, use Dockerfile.strongswan
	IpsecVpnImage string `json:"ipsecVpnImage"`

	// keepalived maintains the ha ip address alive
	// keepalived server need replica 2 at least
	// keepalived represents the keepalived crd name
	// +kubebuilder:validation:Required
	Keepalived string `json:"keepalived"`
}

// VpnGwStatus defines the observed state of VpnGw
type VpnGwStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	Cpu              string              `json:"cpu" patchStrategy:"merge"`
	Memory           string              `json:"memory" patchStrategy:"merge"`
	QoSBandwidth     string              `json:"qosBandwidth" patchStrategy:"merge"`
	Replicas         int32               `json:"replicas" patchStrategy:"merge"`
	Selector         []string            `json:"selector,omitempty" patchStrategy:"merge"`
	Tolerations      []corev1.Toleration `json:"tolerations,omitempty" patchStrategy:"merge"`
	Affinity         corev1.Affinity     `json:"affinity,omitempty" patchStrategy:"merge"`
	EnableSslVpn     bool                `json:"enableSslVpn" patchStrategy:"merge"`
	SslSecret        string              `json:"sslSecret"  patchStrategy:"merge"`
	DhSecret         string              `json:"dhSecret"  patchStrategy:"merge"`
	SslVpnImage      string              `json:"sslVpnImage" patchStrategy:"merge"`
	OvpnCipher       string              `json:"ovpnCipher" patchStrategy:"merge"`
	OvpnProto        string              `json:"ovpnProto" patchStrategy:"merge"`
	OvpnPort         int                 `json:"ovpnPort" patchStrategy:"merge"`
	OvpnSubnetCidr   string              `json:"ovpnSubnetCidr" patchStrategy:"merge"`
	EnableIpsecVpn   bool                `json:"enableIpsecVpn" patchStrategy:"merge"`
	IpsecSecret      string              `json:"ipsecSecret"  patchStrategy:"merge"`
	IpsecVpnImage    string              `json:"ipsecVpnImage" patchStrategy:"merge"`
	IpsecConnections []string            `json:"ipsecConnections,omitempty" patchStrategy:"merge"`
	Keepalived       string              `json:"keepalived" patchStrategy:"merge"`

	// Conditions store the status conditions of the vpn gw instances
	// +operator-sdk:csv:customresourcedefinitions:type=status
	Conditions []metav1.Condition `json:"conditions,omitempty" patchStrategy:"merge" patchMergeKey:"type" protobuf:"bytes,1,rep,name=conditions"`
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status
//+kubebuilder:storageversion
//+kubebuilder:printcolumn:name="IP",type=string,JSONPath=`.spec.ip`
//+kubebuilder:printcolumn:name="PublicIP",type=string,JSONPath=`.spec.publicIp`
//+kubebuilder:printcolumn:name="Subnet",type=string,JSONPath=`.spec.subnet`
//+kubebuilder:printcolumn:name="Cpu",type=string,JSONPath=`.spec.cpu`
//+kubebuilder:printcolumn:name="Mem",type=string,JSONPath=`.spec.memory`
//+kubebuilder:printcolumn:name="QoS",type=string,JSONPath=`.spec.qoSBandwidth`
//+kubebuilder:printcolumn:name="EnableSsl",type=string,JSONPath=`.spec.enableSslVpn`
//+kubebuilder:printcolumn:name="EnableIpsec",type=string,JSONPath=`.spec.enableIpsecVpn`

// VpnGw is the Schema for the vpngws API
type VpnGw struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   VpnGwSpec   `json:"spec,omitempty"`
	Status VpnGwStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// VpnGwList contains a list of VpnGw
type VpnGwList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []VpnGw `json:"items"`
}

func init() {
	SchemeBuilder.Register(&VpnGw{}, &VpnGwList{})
}
