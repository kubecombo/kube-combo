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
)

// log is for logging in this package.
var keepalivedlog = logf.Log.WithName("keepalived-resource")

func (r *KeepAlived) SetupWebhookWithManager(mgr ctrl.Manager) error {
	return ctrl.NewWebhookManagedBy(mgr).
		For(r).
		Complete()
}

// TODO(user): EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!

//+kubebuilder:webhook:path=/mutate-vpn-gw-kubecombo-com-v1-keepalived,mutating=true,failurePolicy=fail,sideEffects=None,groups=vpn-gw.kubecombo.com,resources=keepaliveds,verbs=create;update,versions=v1,name=mkeepalived.kb.io,admissionReviewVersions=v1

// var _ webhook.Defaulter = &KeepAlived{}

// Default implements webhook.Defaulter so a webhook will be registered for the type
func (r *KeepAlived) Default() {
	keepalivedlog.Info("default", "name", r.Name)

	// TODO(user): fill in your defaulting logic.
}

// TODO(user): change verbs to "verbs=create;update;delete" if you want to enable deletion validation.
//+kubebuilder:webhook:path=/validate-vpn-gw-kubecombo-com-v1-keepalived,mutating=false,failurePolicy=fail,sideEffects=None,groups=vpn-gw.kubecombo.com,resources=keepaliveds,verbs=create;update,versions=v1,name=vkeepalived.kb.io,admissionReviewVersions=v1

// var _ webhook.Validator = &KeepAlived{}

// ValidateCreate implements webhook.Validator so a webhook will be registered for the type
func (r *KeepAlived) ValidateCreate() error {
	keepalivedlog.Info("validate create", "name", r.Name)

	// TODO(user): fill in your validation logic upon object creation.
	return nil
}

// ValidateUpdate implements webhook.Validator so a webhook will be registered for the type
func (r *KeepAlived) ValidateUpdate(old runtime.Object) error {
	keepalivedlog.Info("validate update", "name", r.Name)

	// TODO(user): fill in your validation logic upon object update.
	oldKa, _ := old.(*KeepAlived)
	var allErrs field.ErrorList
	if oldKa.Spec.VipV4 != "" && oldKa.Spec.VipV4 != r.Spec.VipV4 {
		err := errors.New("keepalived v4 ip can not be changed")
		e := field.Invalid(field.NewPath("spec").Child("keepAlived"), r.Spec.VipV4, err.Error())
		allErrs = append(allErrs, e)
	}
	if oldKa.Spec.VipV6 != "" && oldKa.Spec.VipV6 != r.Spec.VipV6 {
		err := errors.New("keepalived v6 ip can not be changed")
		e := field.Invalid(field.NewPath("spec").Child("keepAlived"), r.Spec.VipV6, err.Error())
		allErrs = append(allErrs, e)
	}
	if len(allErrs) == 0 {
		return nil
	}
	return nil
}

// ValidateDelete implements webhook.Validator so a webhook will be registered for the type
func (r *KeepAlived) ValidateDelete() error {
	keepalivedlog.Info("validate delete", "name", r.Name)

	// TODO(user): fill in your validation logic upon object deletion.
	return nil
}
