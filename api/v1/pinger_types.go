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

// PingerSpec defines the desired state of Pinger
type PingerSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// cpu, memory request
	// cpu, memory limit
	// 1C 1G at most

	// +kubebuilder:validation:Required
	CPU string `json:"cpu"`

	// +kubebuilder:validation:Required
	Memory string `json:"memory"`

	// +kubebuilder:validation:Required
	Image string `json:"Image"`

	// pinger pod args

	// must reach
	// +kubebuilder:validation:Optional
	// +kubebuilder:default:=False
	MustReach bool `json:"mustReach,omitempty"`

	// defult ping, tcp, udp check interval is 5s
	// +kubebuilder:validation:Optional
	// +kubebuilder:default:=5
	Interval int `json:"interval"`

	// enable metrics
	// +kubebuilder:validation:Optional
	// +kubebuilder:default:=False
	EnableMetric bool `json:"enableMetric"`

	// l2 check ip list, ip1,ip2,ip3
	// +kubebuilder:validation:Optional
	// +kubebuilder:default:=False
	Arpping string `json:"arpPing,omitempty"`

	// l3 check ip list, ip1,ip2,ip3
	// +kubebuilder:validation:Optional
	// +kubebuilder:default:=False
	Ping string `json:"ping,omitempty"`

	// l4 tcp check ip:port list, ip1:port1,ip2:port2,ip3:port3
	// +kubebuilder:validation:Optional
	// +kubebuilder:default:=False
	TcpPing string `json:"tcpPing,omitempty"`

	// l4 udp check ip:port list, ip1:port1,ip2:port2,ip3:port3
	// +kubebuilder:validation:Optional
	// +kubebuilder:default:=False
	UdpPing string `json:"udpPing,omitempty"`

	// l7 dns check ns list, ns1,ns2,ns3
	// +kubebuilder:validation:Optional
	// +kubebuilder:default:=False
	Dns string `json:"dns,omitempty"`
}

// PingerStatus defines the observed state of Pinger
type PingerStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file
	CPU          string `json:"cpu,omitempty"`
	Memory       string `json:"memory,omitempty"`
	Image        string `json:"image,omitempty"`
	Interval     int    `json:"interval,omitempty"`
	EnableMetric bool   `json:"enableMetric,omitempty"`
	MustReach    bool   `json:"mustReach,omitempty"`
	Arpping      string `json:"arpPing,omitempty"`
	Ping         string `json:"ping,omitempty"`
	TcpPing      string `json:"tcpPing,omitempty"`
	UdpPing      string `json:"udpPing,omitempty"`
	Dns          string `json:"dns,omitempty"`

	// Conditions store the status conditions of the vpn gw instances
	// +operator-sdk:csv:customresourcedefinitions:type=status
	Conditions []metav1.Condition `json:"conditions,omitempty" patchStrategy:"merge" patchMergeKey:"type" protobuf:"bytes,1,rep,name=conditions"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

//+kubebuilder:storageversion
//+kubebuilder:printcolumn:name="MustReach",type=bool,JSONPath=`.spec.mustReach`
//+kubebuilder:printcolumn:name="Interval",type=integer,JSONPath=`.spec.interval`
//+kubebuilder:printcolumn:name="EnableMetric",type=bool,JSONPath=`.spec.enableMetric`

// Pinger is the Schema for the pingers API
type Pinger struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   PingerSpec   `json:"spec,omitempty"`
	Status PingerStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// PingerList contains a list of Pinger
type PingerList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Pinger `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Pinger{}, &PingerList{})
}
