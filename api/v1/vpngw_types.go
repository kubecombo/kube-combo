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
	// +kubebuilder:validation:Optional
	Keepalived string `json:"keepalived"`

	// k8s workload type
	// statefulset means use statefulset pod to provide vpn server
	// static means use static pod to provide vpn server

	// +kubebuilder:validation:Required
	WorkloadType string `json:"workloadType"`

	// cpu, memory request
	// cpu, memory limit
	// 1C 1G at least

	// +kubebuilder:validation:Required
	CPU string `json:"cpu"`

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
	SslVpnSecret string `json:"sslVpnSecret,omitempty"`

	// ssl vpn dh secret name, the secret should in the same namespace as the vpn gw
	DhSecret     string `json:"dhSecret,omitempty"`
	SslVpnCipher string `json:"sslVpnCipher"`
	SslVpnAuth   string `json:"sslVpnAuth"`

	// ssl vpn use openvpn server
	// ssl vpn proto, udp or tcp, udp probably is better
	// +kubebuilder:default:=udp
	SslVpnProto string `json:"sslVpnProto"`

	// SslVpn ssl vpn clinet server subnet cidr 10.240.0.0/16
	SslVpnSubnetCidr string `json:"sslVpnSubnetCidr"`

	// ssl vpn server image, use Dockerfile.openvpn
	SslVpnImage string `json:"sslVpnImage"`

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
}

// VpnGwStatus defines the observed state of VpnGw
type VpnGwStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	CPU              string              `json:"cpu" patchStrategy:"merge"`
	Memory           string              `json:"memory" patchStrategy:"merge"`
	QoSBandwidth     string              `json:"qosBandwidth" patchStrategy:"merge"`
	Replicas         int32               `json:"replicas" patchStrategy:"merge"`
	Selector         []string            `json:"selector,omitempty" patchStrategy:"merge"`
	Tolerations      []corev1.Toleration `json:"tolerations,omitempty" patchStrategy:"merge"`
	Affinity         corev1.Affinity     `json:"affinity,omitempty" patchStrategy:"merge"`
	EnableSslVpn     bool                `json:"enableSslVpn" patchStrategy:"merge"`
	SslVpnSecret     string              `json:"sslVpnSecret"  patchStrategy:"merge"`
	DhSecret         string              `json:"dhSecret"  patchStrategy:"merge"`
	SslVpnImage      string              `json:"sslVpnImage" patchStrategy:"merge"`
	SslVpnCipher     string              `json:"sslVpnCipher" patchStrategy:"merge"`
	SslVpnAuth       string              `json:"sslVpnAuth" patchStrategy:"merge"`
	SslVpnProto      string              `json:"sslVpnProto" patchStrategy:"merge"`
	SslVpnPort       int32               `json:"sslVpnPort" patchStrategy:"merge"`
	SslVpnSubnetCidr string              `json:"sslVpnSubnetCidr" patchStrategy:"merge"`
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
//+kubebuilder:printcolumn:name="Keepalived",type=string,JSONPath=`.spec.keepalived`
//+kubebuilder:printcolumn:name="EnableSsl",type=string,JSONPath=`.spec.enableSslVpn`
//+kubebuilder:printcolumn:name="EnableIpsec",type=string,JSONPath=`.spec.enableIpsecVpn`
//+kubebuilder:printcolumn:name="Cpu",type=string,JSONPath=`.Spec.CPU`
//+kubebuilder:printcolumn:name="Mem",type=string,JSONPath=`.spec.memory`
//+kubebuilder:printcolumn:name="QoS",type=string,JSONPath=`.spec.qosBandwidth`
//+kubebuilder:printcolumn:name="WorkloadType",type=string,JSONPath=`.spec.workloadType`

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
