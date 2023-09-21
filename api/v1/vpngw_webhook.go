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
	"fmt"

	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/validation/field"
	ctrl "sigs.k8s.io/controller-runtime"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/webhook"
)

// log is for logging in this package.
var vpngwlog = logf.Log.WithName("vpngw-resource")

func (r *VpnGw) SetupWebhookWithManager(mgr ctrl.Manager) error {
	return ctrl.NewWebhookManagedBy(mgr).
		For(r).
		Complete()
}

// TODO(user): EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!

//+kubebuilder:webhook:path=/mutate-vpn-gw-kubecombo-com-v1-vpngw,mutating=true,failurePolicy=fail,sideEffects=None,groups=vpn-gw.kubecombo.com,resources=vpngws,verbs=create;update,versions=v1,name=mvpngw.kb.io,admissionReviewVersions=v1

var _ webhook.Defaulter = &VpnGw{}

// Default implements webhook.Defaulter so a webhook will be registered for the type
func (r *VpnGw) Default() {
	vpngwlog.Info("default", "name", r.Name)

	// TODO(user): fill in your defaulting logic.
}

// TODO(user): change verbs to "verbs=create;update;delete" if you want to enable deletion validation.
//+kubebuilder:webhook:path=/validate-vpn-gw-kubecombo-com-v1-vpngw,mutating=false,failurePolicy=fail,sideEffects=None,groups=vpn-gw.kubecombo.com,resources=vpngws,verbs=create;update,versions=v1,name=vvpngw.kb.io,admissionReviewVersions=v1

var _ webhook.Validator = &VpnGw{}

// ValidateCreate implements webhook.Validator so a webhook will be registered for the type
func (r *VpnGw) ValidateCreate() error {
	vpngwlog.Info("validate create", "name", r.Name)

	// TODO(user): fill in your validation logic upon object creation.
	if err := r.validateVpnGw(); err != nil {
		return err
	}
	return nil
}

// ValidateUpdate implements webhook.Validator so a webhook will be registered for the type
func (r *VpnGw) ValidateUpdate(old runtime.Object) error {
	vpngwlog.Info("validate update", "name", r.Name)

	// TODO(user): fill in your validation logic upon object update.
	if err := r.validateVpnGw(); err != nil {
		return err
	}
	oldVpnGw, _ := old.(*VpnGw)
	var allErrs field.ErrorList
	if oldVpnGw.Spec.Keepalived != "" && oldVpnGw.Spec.Keepalived != r.Spec.Keepalived {
		err := fmt.Errorf("vpn gw keepalived not support change")
		e := field.Invalid(field.NewPath("spec").Child("keepalived"), r.Spec.Keepalived, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.DhSecret != "" && oldVpnGw.Spec.DhSecret != r.Spec.DhSecret {
		err := fmt.Errorf("vpn gw dh secret not support change")
		e := field.Invalid(field.NewPath("spec").Child("dhSecret"), r.Spec.DhSecret, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.SslSecret != "" && oldVpnGw.Spec.SslSecret != r.Spec.SslSecret {
		err := fmt.Errorf("vpn gw ssl secret not support change")
		e := field.Invalid(field.NewPath("spec").Child("sslSecret"), r.Spec.SslSecret, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.IpsecSecret != "" && oldVpnGw.Spec.IpsecSecret != r.Spec.IpsecSecret {
		err := fmt.Errorf("vpn gw ipsec secret not support change")
		e := field.Invalid(field.NewPath("spec").Child("ipsecSecret"), r.Spec.IpsecSecret, err.Error())
		allErrs = append(allErrs, e)
	}

	if oldVpnGw.Spec.OvpnProto != "" && oldVpnGw.Spec.OvpnProto != r.Spec.OvpnProto {
		err := fmt.Errorf("vpn gw ovpn proto not support change")
		e := field.Invalid(field.NewPath("spec").Child("ovpnProto"), r.Spec.OvpnProto, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.OvpnPort != 0 && oldVpnGw.Spec.OvpnPort != r.Spec.OvpnPort {
		err := fmt.Errorf("vpn gw ovpn port not support change")
		e := field.Invalid(field.NewPath("spec").Child("ovpnPort"), r.Spec.OvpnPort, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.OvpnSubnetCidr != "" && oldVpnGw.Spec.OvpnSubnetCidr != r.Spec.OvpnSubnetCidr {
		err := fmt.Errorf("vpn gw ovpn subnet cidr not support change")
		e := field.Invalid(field.NewPath("spec").Child("ovpnSubnetCidr"), r.Spec.OvpnSubnetCidr, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.Keepalived != "" && oldVpnGw.Spec.Keepalived != r.Spec.Keepalived {
		err := fmt.Errorf("vpn gw keepalived not support change")
		e := field.Invalid(field.NewPath("spec").Child("keepalived"), r.Spec.Keepalived, err.Error())
		allErrs = append(allErrs, e)
	}

	if len(allErrs) != 0 {
		return allErrs.ToAggregate()
	}

	return nil
}

// ValidateDelete implements webhook.Validator so a webhook will be registered for the type
func (r *VpnGw) ValidateDelete() error {
	vpngwlog.Info("validate delete", "name", r.Name)

	// TODO(user): fill in your validation logic upon object deletion.
	return nil
}

func (r *VpnGw) validateVpnGw() error {
	var allErrs field.ErrorList

	if r.Spec.Keepalived == "" {
		err := fmt.Errorf("vpn gw keepalived is required")
		e := field.Invalid(field.NewPath("spec").Child("keepalived"), r.Spec.Keepalived, err.Error())
		allErrs = append(allErrs, e)
	}

	if r.Spec.Cpu == "" || r.Spec.Memory == "" {
		err := fmt.Errorf("vpn gw cpu and memory is required")
		e := field.Invalid(field.NewPath("spec").Child("cpu"), r.Spec.Cpu, err.Error())
		allErrs = append(allErrs, e)
	}

	if r.Spec.QoSBandwidth == "" || r.Spec.QoSBandwidth == "0" {
		err := fmt.Errorf("vpn gw qos bandwidth is required")
		e := field.Invalid(field.NewPath("spec").Child("qosBandwidth"), r.Spec.QoSBandwidth, err.Error())
		allErrs = append(allErrs, e)
	}

	if r.Spec.Keepalived == "" {
		err := fmt.Errorf("vpn gw keepalived is required")
		e := field.Invalid(field.NewPath("spec").Child("keepalived"), r.Spec.Keepalived, err.Error())
		allErrs = append(allErrs, e)
	}

	if r.Spec.Replicas != 1 {
		err := fmt.Errorf("vpn gw replicas should only be 1 for now, ha mode will be supported in the future")
		e := field.Invalid(field.NewPath("spec").Child("replicas"), r.Spec.Replicas, err.Error())
		allErrs = append(allErrs, e)
	}

	if !r.Spec.EnableSslVpn && !r.Spec.EnableIpsecVpn {
		err := fmt.Errorf("either ssl vpn or ipsec vpn should be enabled")
		e := field.Invalid(field.NewPath("spec").Child("enableSslVpn"), r.Spec.EnableSslVpn, err.Error())
		allErrs = append(allErrs, e)
	}

	if r.Spec.EnableSslVpn {
		if r.Spec.DhSecret == "" {
			err := fmt.Errorf("ssl vpn dh secret is required")
			e := field.Invalid(field.NewPath("spec").Child("dhSecret"), r.Spec.DhSecret, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.SslSecret == "" {
			err := fmt.Errorf("ssl vpn secret is required")
			e := field.Invalid(field.NewPath("spec").Child("sslSecret"), r.Spec.SslSecret, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.OvpnCipher == "" {
			err := fmt.Errorf("ssl vpn cipher is required")
			e := field.Invalid(field.NewPath("spec").Child("ovpnCipher"), r.Spec.OvpnCipher, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.OvpnProto == "" {
			err := fmt.Errorf("ssl vpn proto is required")
			e := field.Invalid(field.NewPath("spec").Child("ovpnProto"), r.Spec.OvpnProto, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.OvpnPort != 1149 && r.Spec.OvpnPort != 443 {
			err := fmt.Errorf("ssl vpn port is required")
			e := field.Invalid(field.NewPath("spec").Child("ovpnPort"), r.Spec.OvpnPort, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.OvpnSubnetCidr == "" {
			err := fmt.Errorf("ssl vpn subnet cidr is required")
			e := field.Invalid(field.NewPath("spec").Child("ovpnSubnetCidr"), r.Spec.OvpnSubnetCidr, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.OvpnProto != "udp" && r.Spec.OvpnProto != "tcp" {
			err := fmt.Errorf("ssl vpn proto should be udp or tcp")
			e := field.Invalid(field.NewPath("spec").Child("ovpnProto"), r.Spec.OvpnProto, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.OvpnProto == "udp" && r.Spec.OvpnPort != 1149 {
			err := fmt.Errorf("ssl vpn port should be 1149 when proto is udp")
			e := field.Invalid(field.NewPath("spec").Child("ovpnPort"), r.Spec.OvpnPort, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.OvpnProto == "tcp" && r.Spec.OvpnPort != 443 {
			err := fmt.Errorf("ssl vpn port should be 443 when proto is tcp")
			e := field.Invalid(field.NewPath("spec").Child("ovpnPort"), r.Spec.OvpnPort, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.SslVpnImage == "" {
			err := fmt.Errorf("ssl vpn image is required")
			e := field.Invalid(field.NewPath("spec").Child("sslVpnImage"), r.Spec.SslVpnImage, err.Error())
			allErrs = append(allErrs, e)
		}
	}

	if r.Spec.EnableIpsecVpn {
		if r.Spec.IpsecSecret == "" {
			err := fmt.Errorf("ipsec vpn secret is required")
			e := field.Invalid(field.NewPath("spec").Child("ipsecSecret"), r.Spec.IpsecSecret, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.IpsecVpnImage == "" {
			err := fmt.Errorf("ipsec vpn image is required")
			e := field.Invalid(field.NewPath("spec").Child("ipsecVpnImage"), r.Spec.IpsecVpnImage, err.Error())
			allErrs = append(allErrs, e)
		}
	}

	if len(allErrs) == 0 {
		return nil
	}

	return allErrs.ToAggregate()
}
