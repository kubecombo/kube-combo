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

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	"github.com/go-logr/logr"
	vpngwv1 "github.com/kubecombo/kube-combo/api/v1"
	"github.com/scylladb/go-set/iset"
	corev1 "k8s.io/api/core/v1"
)

const (
	RouterIDLabel = "router-id"
	SubnetLabel   = "subnet"
)

// KeepAlivedReconciler reconciles a KeepAlived object
type KeepAlivedReconciler struct {
	client.Client
	Scheme    *runtime.Scheme
	Log       logr.Logger
	Namespace string
	Reload    chan event.GenericEvent
}

//+kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=keepaliveds,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=keepaliveds/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=keepaliveds/finalizers,verbs=update

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the KeepAlived object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.14.1/pkg/reconcile
func (r *KeepAlivedReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = log.FromContext(ctx)

	// TODO(user): your logic here
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start reconcile", "keepalived", namespacedName)
	defer r.Log.Info("end reconcile", "keepalived", namespacedName)
	updates.Inc()
	// update ka
	res, err := r.handleAddOrUpdateKeepAlived(ctx, req)
	switch res {
	case SyncStateError:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle keepalived")
		return ctrl.Result{}, errRetry
	case SyncStateErrorNoRetry:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle keepalived")
		return ctrl.Result{}, nil
	}

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *KeepAlivedReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&vpngwv1.KeepAlived{},
			builder.WithPredicates(
				predicate.NewPredicateFuncs(
					func(object client.Object) bool {
						_, ok := object.(*vpngwv1.KeepAlived)
						if !ok {
							err := errors.New("invalid keepalived")
							r.Log.Error(err, "expected keepalived in worequeue but got something else")
							return false
						}
						return true
					},
				),
			),
		).
		Complete(r)
}

func (r *KeepAlivedReconciler) validateKeepAlived(ctx context.Context, ka *vpngwv1.KeepAlived, namespacedName string) error {
	// Check if VRRP authentication is needed and if so extract credentials
	if ka.Spec.PasswordAuth.SecretRef.Name != "" {
		secret := &corev1.Secret{}
		err := r.Get(ctx, types.NamespacedName{Namespace: ka.GetNamespace(), Name: ka.Spec.PasswordAuth.SecretRef.Name}, secret)
		if err != nil {
			// Requeue and log error
			err = fmt.Errorf("could not find secret %s in namespace %s", ka.Spec.PasswordAuth.SecretRef.Name, ka.GetNamespace())
			r.Log.Error(err, "could not find password auth secret", "keepalived", ka)
			return err
		}
		_, ok := secret.Data[ka.Spec.PasswordAuth.SecretKey]
		if !ok {
			// Requeue and log error
			err = fmt.Errorf("could not find key %s in secret %s in namespace %s", ka.Spec.PasswordAuth.SecretKey, ka.Spec.PasswordAuth.SecretRef.Name, ka.GetNamespace())
			r.Log.Error(err, "could not find referenced key in password auth secret", "keepalived", ka)
			return err
		}
	}
	return nil
}

func labelsForKeepAlived(ka *vpngwv1.KeepAlived) map[string]string {
	return map[string]string{
		SubnetLabel: ka.Spec.Subnet,
	}
}

func (r *KeepAlivedReconciler) handleAddOrUpdateKeepAlived(ctx context.Context, req ctrl.Request) (SyncState, error) {
	// create keepalived crd
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start handleAddOrUpdateKeepAlived", "KeepAlived", namespacedName)
	defer r.Log.Info("end handleAddOrUpdateKeepAlived", "KeepAlived", namespacedName)

	// fetch ka
	ka, err := r.getKeepAlived(ctx, req.NamespacedName)
	if err != nil {
		err := fmt.Errorf("failed to get keepalived %s: %w", namespacedName, err)
		r.Log.Error(err, "failed to get keepalived")
		return SyncStateError, err
	}
	if ka == nil {
		return SyncStateErrorNoRetry, nil
	}

	// validate keepalived spec
	if err := r.validateKeepAlived(ctx, ka, namespacedName); err != nil {
		r.Log.Error(err, "failed to validate keepalived")
		// invalid spec no retry
		return SyncStateErrorNoRetry, err
	}

	if err = r.setRouterID(ctx, ka); err != nil {
		err := fmt.Errorf("failed to set router id for keepalived %s: %w", namespacedName, err)
		r.Log.Error(err, "keepalived", ka)
		return SyncStateErrorNoRetry, nil
	}

	// patch lable so that vpn gw can find its keepalived
	newKa := ka.DeepCopy()
	labels := labelsForKeepAlived(newKa)
	newKa.SetLabels(labels)
	err = r.Patch(context.Background(), newKa, client.MergeFrom(ka))
	if err != nil {
		r.Log.Error(err, "failed to update the keepalived")
		return SyncStateError, err
	}
	return SyncStateSuccess, err
}

func (r *KeepAlivedReconciler) setRouterID(ctx context.Context, ka *vpngwv1.KeepAlived) error {
	assignedIDs := []int{}
	// fetch kas
	kas, err := r.listKeepAlived(ctx, ka)
	if err != nil {
		err := fmt.Errorf("failed to get keepaliveds in ns %s: %w", ka.Namespace, err)
		r.Log.Error(err, "failed to get keepaliveds")
		return err
	}
	for _, ka := range *kas {
		if ka.Status.RouterID != 0 {
			assignedIDs = append(assignedIDs, ka.Status.RouterID)
		}
	}
	id, err := findNextAvailableID(assignedIDs)
	if err != nil {
		err := fmt.Errorf("failed to find next available id for keepalived %s: %w", ka.Name, err)
		r.Log.Error(err, "failed to find next available id")
		return err
	}
	ka.Status.RouterID = id
	err = r.Status().Update(ctx, ka)
	if err != nil {
		err := fmt.Errorf("failed to update status for keepalived %s: %w", ka.Name, err)
		r.Log.Error(err, "failed to update status")
		return err
	}
	return nil
}

func findNextAvailableID(ids []int) (int, error) {
	if len(ids) == 0 {
		return 1, nil
	}
	usedSet := iset.New(ids...)
	for i := 1; i <= 255; i++ {
		used := false
		if usedSet.Has(i) {
			used = true
		}
		if !used {
			return i, nil
		}
	}
	return 0, errors.New("cannot allocate more than 255 ids in one keepalived group")
}

func (r *KeepAlivedReconciler) getKeepAlived(ctx context.Context, name types.NamespacedName) (*vpngwv1.KeepAlived, error) {
	var res vpngwv1.KeepAlived
	err := r.Get(ctx, name, &res)
	if apierrors.IsNotFound(err) { // in case of delete, get fails and we need to pass nil to the handler
		return nil, nil
	}
	if err != nil {
		err := fmt.Errorf("failed to get keepalived %s: %w", name.String(), err)
		r.Log.Error(err, "failed to get keepalived")
		return nil, err
	}
	return &res, nil
}

func (r *KeepAlivedReconciler) listKeepAlived(ctx context.Context, ka *vpngwv1.KeepAlived) (*[]vpngwv1.KeepAlived, error) {
	kaList := &vpngwv1.KeepAlivedList{}
	listOps := &client.ListOptions{Namespace: ka.Namespace}
	labelSelector := client.MatchingLabels(labelsForKeepAlived(ka))
	err := r.List(ctx, kaList, listOps, labelSelector)
	if err != nil {
		err := fmt.Errorf("failed to list keepalived %s: %w", ka.Namespace, err)
		r.Log.Error(err, "failed to list keepalived")
		return nil, err
	}
	return &kaList.Items, nil
}
