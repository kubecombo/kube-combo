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
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// IpsecConnSpec defines the desired state of IpsecConn
type IpsecConnSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// reference to: https://docs.strongswan.org/docs/5.9/swanctl/swanctlConf.html#_connections

	// +kubebuilder:validation:Required
	VpnGw string `json:"vpnGw"`

	// Authentication to perform locally.
	// pubkey uses public key authentication based on a private key associated with a usable certificate. psk uses pre-shared key authentication.
	// The IKEv1 specific xauth is used for XAuth or Hybrid authentication while the IKEv2 specific eap keyword defines EAP authentication.

	// +kubebuilder:validation:Required
	Auth string `json:"auth"`
	// 0 accepts both IKEv1 and IKEv2, 1 uses IKEv1 aka ISAKMP, 2 uses IKEv2

	// +kubebuilder:validation:Required
	IkeVersion string `json:"ikeVersion"`

	// A proposal is a set of algorithms.
	// For non-AEAD algorithms this includes IKE an encryption algorithm, an integrity algorithm, a pseudo random function (PRF) and a Diffie-Hellman key exchange group.
	// For AEAD algorithms, instead of encryption and integrity algorithms a combined algorithm is used.
	// With IKEv2 multiple algorithms of the same kind can be specified in a single proposal, from which one gets selected.
	// For IKEv1 only one algorithm per kind is allowed per proposal, more algorithms get implicitly stripped. Use multiple proposals to offer different algorithm combinations with IKEv1.
	//  Algorithm keywords get separated using dashes. Multiple proposals may be separated by commas.
	// The special value default adds a default proposal of supported algorithms considered safe and is usually a good choice for interoperability. [default]

	// +kubebuilder:validation:Required
	IKEProposals string `json:"ikeProposals"`

	// CN is defined in x509 certificate, PSK not required
	// +kubebuilder:validation:Optional
	LocalCN string `json:"localCN"`

	// current public ipsec vpn gw internal keepalived virtual ip
	// +kubebuilder:validation:Required
	LocalVIP string `json:"localVIP"`

	// local vip gateway
	// set it in multi nic env case
	// if the vip gw nic is not use default nic
	// avoid source in souce out problem
	// ipsec gw nic vip always maintained by keepalived
	// auto add static route for ipsec tunnel
	// +kubebuilder:validation:Optional
	LocalGateway string `json:"localGateway"`

	// local vip gateway nic
	// set it in multi nic env case
	// if the vip gw nic is not use default nic
	// avoid source in souce out problem
	// ipsec gw vip nic which may need to disable rp_filter in some linux, 0 or 2 for vpn|lb
	// only one nic should be enough for ipsec gw
	// +kubebuilder:validation:Optional
	LocalGatewayNic string `json:"localGatewayNic"`

	// current public ipsec vpn gw external ip
	// +kubebuilder:validation:Required
	LocalEIP string `json:"localEIP"`

	// +kubebuilder:validation:Required
	LocalPrivateCidrs string `json:"localPrivateCidrs"`

	// +kubebuilder:validation:Optional
	RemoteCN string `json:"remoteCN"`

	// remote public ipsec vpn gw external ip
	// +kubebuilder:validation:Required
	RemoteEIP string `json:"remoteEIP"`

	// +kubebuilder:validation:Required
	RemotePrivateCidrs string `json:"remotePrivateCidrs"`

	// +kubebuilder:validation:Optional
	ESPProposals string `json:"espProposals,omitempty"`
}

// type IpsecConnStatus struct {
// }

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:storageversion
// +kubebuilder:resource:shortName=conn
// +kubebuilder:printcolumn:name="VpnGw",type=string,JSONPath=`.spec.vpnGw`
// +kubebuilder:printcolumn:name="LocalVIP",type=string,JSONPath=`.spec.localVIP`
// +kubebuilder:printcolumn:name="LocalEIP",type=string,JSONPath=`.spec.localEIP`
// +kubebuilder:printcolumn:name="RemoteEIP",type=string,JSONPath=`.spec.remoteEIP`
// +kubebuilder:printcolumn:name="LocalPrivateCidrs",type=string,JSONPath=`.spec.localPrivateCidrs`
// +kubebuilder:printcolumn:name="RemotePrivateCidrs",type=string,JSONPath=`.spec.remotePrivateCidrs`

// IpsecConn is the Schema for the ipsecconns API
type IpsecConn struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec IpsecConnSpec `json:"spec,omitempty"`
	// Status IpsecConnStatus `json:"status,omitempty"`  // TODO: add status if needed
}

//+kubebuilder:object:root=true

// IpsecConnList contains a list of IpsecConn
type IpsecConnList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []IpsecConn `json:"items"`
}

func init() {
	SchemeBuilder.Register(&IpsecConn{}, &IpsecConnList{})
}
