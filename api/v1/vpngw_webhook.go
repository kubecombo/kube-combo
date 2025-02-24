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
	"errors"

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
		vpngwlog.Error(err, "validate vpn gw failed")
		return err
	}
	return nil
}

// ValidateUpdate implements webhook.Validator so a webhook will be registered for the type
func (r *VpnGw) ValidateUpdate(old runtime.Object) error {
	vpngwlog.Info("validate update", "name", r.Name)

	// TODO(user): fill in your validation logic upon object update.
	if err := r.validateVpnGw(); err != nil {
		vpngwlog.Error(err, "validate vpn gw failed")
		return err
	}
	oldVpnGw, _ := old.(*VpnGw)
	var allErrs field.ErrorList
	if oldVpnGw.Spec.Keepalived != "" && oldVpnGw.Spec.Keepalived != r.Spec.Keepalived {
		err := errors.New("vpn gw keepalived not support change")
		e := field.Invalid(field.NewPath("spec").Child("keepalived"), r.Spec.Keepalived, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.DhSecret != "" && oldVpnGw.Spec.DhSecret != r.Spec.DhSecret {
		err := errors.New("vpn gw dh secret not support change")
		e := field.Invalid(field.NewPath("spec").Child("dhSecret"), r.Spec.DhSecret, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.SslVpnSecret != "" && oldVpnGw.Spec.SslVpnSecret != r.Spec.SslVpnSecret {
		err := errors.New("vpn gw ssl secret not support change")
		e := field.Invalid(field.NewPath("spec").Child("sslVpnSecret"), r.Spec.SslVpnSecret, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.IpsecSecret != "" && oldVpnGw.Spec.IpsecSecret != r.Spec.IpsecSecret {
		err := errors.New("vpn gw ipsec secret not support change")
		e := field.Invalid(field.NewPath("spec").Child("ipsecSecret"), r.Spec.IpsecSecret, err.Error())
		allErrs = append(allErrs, e)
	}

	if oldVpnGw.Spec.SslVpnProto != "" && oldVpnGw.Spec.SslVpnProto != r.Spec.SslVpnProto {
		err := errors.New("vpn gw SslVpn proto not support change")
		e := field.Invalid(field.NewPath("spec").Child("SslVpnProto"), r.Spec.SslVpnProto, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.SslVpnSubnetCidr != "" && oldVpnGw.Spec.SslVpnSubnetCidr != r.Spec.SslVpnSubnetCidr {
		err := errors.New("vpn gw SslVpn subnet cidr not support change")
		e := field.Invalid(field.NewPath("spec").Child("SslVpnSubnetCidr"), r.Spec.SslVpnSubnetCidr, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldVpnGw.Spec.Keepalived != "" && oldVpnGw.Spec.Keepalived != r.Spec.Keepalived {
		err := errors.New("vpn gw keepalived not support change")
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
		err := errors.New("vpn gw keepalived is required")
		e := field.Invalid(field.NewPath("spec").Child("keepalived"), r.Spec.Keepalived, err.Error())
		allErrs = append(allErrs, e)
	}

	if r.Spec.CPU == "" || r.Spec.Memory == "" {
		err := errors.New("vpn gw cpu and memory is required, 1C 1Gi at least")
		e := field.Invalid(field.NewPath("spec").Child("cpu"), r.Spec.CPU, err.Error())
		allErrs = append(allErrs, e)
	}

	// TODO:// maker sure the cpu and memory 1c1g at least

	if r.Spec.QoSBandwidth == "" || r.Spec.QoSBandwidth == "0" {
		err := errors.New("vpn gw qos bandwidth is required")
		e := field.Invalid(field.NewPath("spec").Child("qosBandwidth"), r.Spec.QoSBandwidth, err.Error())
		allErrs = append(allErrs, e)
	}

	// user may use its own keepalived in the host-network static pod case
	// skip check keepalived image

	if !r.Spec.EnableSslVpn && !r.Spec.EnableIpsecVpn {
		err := errors.New("either ssl vpn or ipsec vpn should be enabled")
		e := field.Invalid(field.NewPath("spec").Child("enableSslVpn"), r.Spec.EnableSslVpn, err.Error())
		allErrs = append(allErrs, e)
	}

	if r.Spec.EnableSslVpn {
		if r.Spec.DhSecret == "" {
			err := errors.New("ssl vpn dh secret is required")
			e := field.Invalid(field.NewPath("spec").Child("dhSecret"), r.Spec.DhSecret, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.SslVpnSecret == "" {
			err := errors.New("ssl vpn secret is required")
			e := field.Invalid(field.NewPath("spec").Child("sslVpnSecret"), r.Spec.SslVpnSecret, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.SslVpnCipher == "" {
			err := errors.New("ssl vpn cipher is required")
			e := field.Invalid(field.NewPath("spec").Child("SslVpnCipher"), r.Spec.SslVpnCipher, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.SslVpnProto == "" {
			err := errors.New("ssl vpn proto is required")
			e := field.Invalid(field.NewPath("spec").Child("SslVpnProto"), r.Spec.SslVpnProto, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.SslVpnSubnetCidr == "" {
			err := errors.New("ssl vpn subnet cidr is required")
			e := field.Invalid(field.NewPath("spec").Child("SslVpnSubnetCidr"), r.Spec.SslVpnSubnetCidr, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.SslVpnProto != "udp" && r.Spec.SslVpnProto != "tcp" {
			err := errors.New("ssl vpn proto should be udp or tcp")
			e := field.Invalid(field.NewPath("spec").Child("SslVpnProto"), r.Spec.SslVpnProto, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.SslVpnImage == "" {
			err := errors.New("ssl vpn image is required")
			e := field.Invalid(field.NewPath("spec").Child("sslVpnImage"), r.Spec.SslVpnImage, err.Error())
			allErrs = append(allErrs, e)
		}
	}

	if r.Spec.EnableIpsecVpn {
		if r.Spec.IpsecSecret == "" {
			err := errors.New("ipsec vpn secret is required")
			e := field.Invalid(field.NewPath("spec").Child("ipsecSecret"), r.Spec.IpsecSecret, err.Error())
			allErrs = append(allErrs, e)
		}
		if r.Spec.IpsecVpnImage == "" {
			err := errors.New("ipsec vpn image is required")
			e := field.Invalid(field.NewPath("spec").Child("ipsecVpnImage"), r.Spec.IpsecVpnImage, err.Error())
			allErrs = append(allErrs, e)
		}
	}

	if len(allErrs) == 0 {
		return nil
	}

	return allErrs.ToAggregate()
}
