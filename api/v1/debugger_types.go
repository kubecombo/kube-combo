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

// DebuggerSpec defines the desired state of Debugger
type DebuggerSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// k8s workload type
	// one pod or daemonset

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
	// +kubebuilder:validation:Optional
	QoSBandwidth string `json:"qosBandwidth"`

	// kube-ovn subnet
	// +kubebuilder:validation:Optional
	Subnet string `json:"subnet,omitempty"`

	// hostnetwork pod
	// default is false
	// +kubebuilder:validation:Optional
	// +kubebuilder:default:=false
	HostNetwork bool `json:"hostNetwork,omitempty"`

	// debugger default image
	// +kubebuilder:validation:Optional
	// +kubebuilder:default:="kubecombo/debugger:latest"
	Image string `json:"image,omitempty"`

	// pod node selector
	// +kubebuilder:validation:Optional
	Selector []string `json:"selector,omitempty"`

	// pod tolerations
	// +kubebuilder:validation:Optional
	Tolerations []corev1.Toleration `json:"tolerations,omitempty"`

	// pod affinity
	// +kubebuilder:validation:Optional
	Affinity corev1.Affinity `json:"affinity,omitempty"`

	// deployment pod spec node name
	// +kubebuilder:validation:Optional
	NodeName string `json:"nodeName,omitempty"`

	// control pinger pod lifecycle
	// enable to start pinger pod
	// disable to stop pinger pod
	// +kubebuilder:validation:Optional
	EnablePinger bool `json:"enablePinger,omitempty"`

	// pinger CRD
	Pinger string `json:"pinger,omitempty"`
}

// DebuggerStatus defines the observed state of Debugger
type DebuggerStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	WorkloadType string              `json:"workloadType" patchStrategy:"merge"`
	CPU          string              `json:"cpu" patchStrategy:"merge"`
	Memory       string              `json:"memory" patchStrategy:"merge"`
	QoSBandwidth string              `json:"qosBandwidth" patchStrategy:"merge"`
	Subnet       string              `json:"subnet,omitempty" patchStrategy:"merge"`
	HostNetwork  bool                `json:"hostNetwork,omitempty" patchStrategy:"merge"`
	Image        string              `json:"image,omitempty" patchStrategy:"merge"`
	Selector     []string            `json:"selector,omitempty" patchStrategy:"merge"`
	Tolerations  []corev1.Toleration `json:"tolerations,omitempty" patchStrategy:"merge"`
	Affinity     corev1.Affinity     `json:"affinity,omitempty" patchStrategy:"merge"`
	NodeName     string              `json:"nodeName,omitempty" patchStrategy:"merge"`
	EnablePinger bool                `json:"enablePinger,omitempty" patchStrategy:"merge"`
	Pinger       string              `json:"pinger,omitempty" patchStrategy:"merge"`

	// Conditions store the status conditions of the vpn gw instances
	// +operator-sdk:csv:customresourcedefinitions:type=status
	Conditions []metav1.Condition `json:"conditions,omitempty" patchStrategy:"merge" patchMergeKey:"type" protobuf:"bytes,1,rep,name=conditions"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:storageversion
// +kubebuilder:resource:shortName=debug
// +kubebuilder:printcolumn:name="CPU",type=string,JSONPath=`.spec.cpu`
// +kubebuilder:printcolumn:name="Memory",type=string,JSONPath=`.spec.memory`
// +kubebuilder:printcolumn:name="Host Network",type=boolean,JSONPath
// +kubebuilder:printcolumn:name="Subnet",type=string,JSONPath=`.spec.subnet`
// +kubebuilder:printcolumn:name="Workload",type=string,JSONPath=`.spec.workloadType`
// +kubebuilder:printcolumn:name="Pinger",type=string,JSONPath=`.spec.pinger`
// +kubebuilder:printcolumn:name="Image",type=string,JSONPath=`.spec.image`

// Debugger is the Schema for the debuggers API
type Debugger struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   DebuggerSpec   `json:"spec,omitempty"`
	Status DebuggerStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// DebuggerList contains a list of Debugger
type DebuggerList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []Debugger `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Debugger{}, &DebuggerList{})
}
