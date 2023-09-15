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

// PasswordAuth references a Kubernetes secret to extract the password for VRRP authentication
type PasswordAuth struct {
	// +required
	SecretRef corev1.LocalObjectReference `json:"secretRef"`

	// +optional
	// +kubebuilder:default:=password
	SecretKey string `json:"secretKey"`
}

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// KeepAlivedSpec defines the desired state of KeepAlived
type KeepAlivedSpec struct {
	// INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// +kubebuilder:validation:Required
	// +kubebuilder:default:=kubecombo.io/keepalived:latest
	Image string `json:"image"`

	// +kubebuilder:validation:Required
	// +kubebuilder:default:=vpc1-subnet1
	Subnet string `json:"subnet"`

	// +kubebuilder:validation:Required
	// +kubebuilder:default:=192.168.0.1
	Vip string `json:"vip"`

	// +optional
	PasswordAuth PasswordAuth `json:"passwordAuth,omitempty"`

	// +kubebuilder:validation:Optional
	// +mapType=granular
	VerbatimConfig map[string]string `json:"verbatimConfig,omitempty"`

	// +optional
	UnicastEnabled bool `json:"unicastEnabled,omitempty"`
}

// KeepAlivedStatus defines the observed state of KeepAlived
type KeepAlivedStatus struct {
	// INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
	// Important: Run "make" to regenerate code after modifying this file

	// +patchMergeKey=type
	// +patchStrategy=merge
	// +listType=map
	// +listMapKey=type
	Conditions []metav1.Condition `json:"conditions,omitempty" patchStrategy:"merge" patchMergeKey:"type"`

	// +kubebuilder:validation:Required
	// +kubebuilder:default:=0
	RouterID int `json:"routerID"`
}

func (m *KeepAlived) GetConditions() []metav1.Condition {
	return m.Status.Conditions
}

func (m *KeepAlived) SetConditions(conditions []metav1.Condition) {
	m.Status.Conditions = conditions
}

//+kubebuilder:object:root=true
//+kubebuilder:subresource:status

// KeepAlived is the Schema for the keepaliveds API
type KeepAlived struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   KeepAlivedSpec   `json:"spec,omitempty"`
	Status KeepAlivedStatus `json:"status,omitempty"`
}

//+kubebuilder:object:root=true

// KeepAlivedList contains a list of KeepAlived
type KeepAlivedList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []KeepAlived `json:"items"`
}

func init() {
	SchemeBuilder.Register(&KeepAlived{}, &KeepAlivedList{})
}
