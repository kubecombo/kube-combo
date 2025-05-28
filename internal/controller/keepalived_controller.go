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

	"github.com/go-logr/logr"
	"github.com/scylladb/go-set/iset"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	myv1 "github.com/kubecombo/kube-combo/api/v1"
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
	if err != nil {
		r.Log.Error(err, "failed to handle keepalived")
	}
	switch res {
	case SyncStateError:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle keepalived, will retry")
		return ctrl.Result{}, errRetry
	case SyncStateErrorNoRetry:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle keepalived, will not retry")
		return ctrl.Result{}, nil
	}

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *KeepAlivedReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&myv1.KeepAlived{},
			builder.WithPredicates(
				predicate.NewPredicateFuncs(
					func(object client.Object) bool {
						_, ok := object.(*myv1.KeepAlived)
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

func (r *KeepAlivedReconciler) handleAddOrUpdateKeepAlived(ctx context.Context, req ctrl.Request) (SyncState, error) {
	// create keepalived crd
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start handleAddOrUpdateKeepAlived", "KeepAlived", namespacedName)
	defer r.Log.Info("end handleAddOrUpdateKeepAlived", "KeepAlived", namespacedName)

	// fetch ka
	ka, err := r.getKeepAlived(ctx, req.NamespacedName)
	if err != nil {
		r.Log.Error(err, "failed to get keepalived")
		return SyncStateError, err
	}
	if ka == nil {
		// ka is deleted
		return SyncStateSuccess, nil
	}
	if ka.Status.RouterID != 0 {
		// ka is already handled
		return SyncStateSuccess, nil
	}

	if err = r.setRouterID(ctx, ka); err != nil {
		r.Log.Error(err, "failed to set router id")
		return SyncStateErrorNoRetry, err
	}

	return SyncStateSuccess, nil
}

func (r *KeepAlivedReconciler) setRouterID(ctx context.Context, ka *myv1.KeepAlived) error {
	assignedIDs := []int{}
	kas, err := r.listKeepAlived(ctx, ka.Namespace)
	if err != nil {
		r.Log.Error(err, "failed to list keepaliveds")
		return err
	}
	for _, ka := range *kas {
		if ka.Status.RouterID != 0 {
			assignedIDs = append(assignedIDs, ka.Status.RouterID)
		}
	}
	id, err := findNextAvailableID(assignedIDs)
	if err != nil {
		r.Log.Error(err, "failed to find next available id")
		return err
	}
	ka.Status.RouterID = id
	err = r.Update(ctx, ka)
	if err != nil {
		r.Log.Error(err, "failed to update keepalived router id")
		return err
	}
	return nil
}

func findNextAvailableID(usedIDs []int) (int, error) {
	if len(usedIDs) == 0 {
		return 1, nil
	}
	usedSet := iset.New(usedIDs...)
	for i := 1; i <= 255; i++ {
		if !usedSet.Has(i) {
			return i, nil
		}
	}
	return 0, errors.New("cannot allocate more than 255 ids in one keepalived group")
}

func (r *KeepAlivedReconciler) getKeepAlived(ctx context.Context, name types.NamespacedName) (*myv1.KeepAlived, error) {
	var res myv1.KeepAlived
	err := r.Get(ctx, name, &res)
	if apierrors.IsNotFound(err) { // in case of delete, get fails and we need to pass nil to the handler
		return nil, nil
	}
	if err != nil {
		r.Log.Error(err, "failed to get keepalived")
		return nil, err
	}
	return &res, nil
}

func (r *KeepAlivedReconciler) listKeepAlived(ctx context.Context, ns string) (*[]myv1.KeepAlived, error) {
	kaList := &myv1.KeepAlivedList{}
	listOps := &client.ListOptions{Namespace: ns}
	err := r.List(ctx, kaList, listOps)
	if err != nil {
		r.Log.Error(err, "failed to list keepalived")
		return nil, err
	}
	return &kaList.Items, nil
}
