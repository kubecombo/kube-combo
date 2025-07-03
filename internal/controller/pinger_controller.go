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
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	myv1 "github.com/kubecombo/kube-combo/api/v1"
)

// PingerReconciler reconciles a Pinger object
type PingerReconciler struct {
	client.Client
	Scheme    *runtime.Scheme
	Log       logr.Logger
	Namespace string
	Reload    chan ctrl.Request
}

// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=pingers,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=pingers/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=pingers/finalizers,verbs=update

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the Pinger object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.19.0/pkg/reconcile
func (r *PingerReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = log.FromContext(ctx)

	// TODO(user): your logic here
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start reconcile", "pinger", namespacedName)
	defer r.Log.Info("end reconcile", "pinger", namespacedName)
	updates.Inc()
	// update pinger
	res, err := r.handleAddOrUpdatePinger(ctx, req)
	if err != nil {
		r.Log.Error(err, "failed to handle pinger")
	}
	switch res {
	case SyncStateError:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle pinger, will retry")
		return ctrl.Result{}, errRetry
	case SyncStateErrorNoRetry:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle pinger, not retry")
		return ctrl.Result{}, nil
	}

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *PingerReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&myv1.Pinger{},
			builder.WithPredicates(
				predicate.NewPredicateFuncs(
					func(object client.Object) bool {
						_, ok := object.(*myv1.Pinger)
						if !ok {
							err := errors.New("invalid pinger")
							r.Log.Error(err, "expected pinger in workqueue but got something else")
							return false
						}
						return true
					},
				),
			),
		).
		Complete(r)
}

func (r *PingerReconciler) handleAddOrUpdatePinger(ctx context.Context, req ctrl.Request) (SyncState, error) {
	// create pinger crd
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start handleAddOrUpdatepinger", "pinger", namespacedName)
	defer r.Log.Info("end handleAddOrUpdatepinger", "pinger", namespacedName)

	// fetch pinger
	pinger, err := r.getPinger(ctx, req.NamespacedName)
	if err != nil {
		r.Log.Error(err, "failed to get pinger")
		return SyncStateError, err
	}
	if pinger == nil {
		// ka is deleted
		return SyncStateSuccess, nil
	}

	if needsync := r.needSync(pinger); !needsync {
		r.Log.Info("pinger is up to date, no need to sync", "pinger", pinger.Name)
		return SyncStateSuccess, nil
	}

	if err = r.syncPinger(ctx, pinger); err != nil {
		r.Log.Error(err, "failed to set router id")
		return SyncStateErrorNoRetry, err
	}

	return SyncStateSuccess, nil
}

func (r *PingerReconciler) getPinger(ctx context.Context, name types.NamespacedName) (*myv1.Pinger, error) {
	pinger := &myv1.Pinger{}
	err := r.Get(ctx, name, pinger)
	if apierrors.IsNotFound(err) { // in case of delete, get fails and we need to pass nil to the handler
		return nil, nil
	}
	if err != nil {
		r.Log.Error(err, "failed to get pinger")
		return nil, err
	}
	return pinger, nil
}

func (r *PingerReconciler) syncPinger(ctx context.Context, pinger *myv1.Pinger) error {
	r.Log.Info("sync pinger", "pinger", pinger.Name)
	needUpdate := false
	if pinger.Status.Image != pinger.Spec.Image {
		pinger.Status.Image = pinger.Spec.Image
		needUpdate = true
	}
	if pinger.Status.EnableMetrics != pinger.Spec.EnableMetrics {
		pinger.Status.EnableMetrics = pinger.Spec.EnableMetrics
		needUpdate = true
	}
	if pinger.Status.Ping != pinger.Spec.Ping {
		pinger.Status.Ping = pinger.Spec.Ping
		needUpdate = true
	}
	if pinger.Status.TcpPing != pinger.Spec.TcpPing {
		pinger.Status.TcpPing = pinger.Spec.TcpPing
		needUpdate = true
	}
	if pinger.Status.UdpPing != pinger.Spec.UdpPing {
		pinger.Status.UdpPing = pinger.Spec.UdpPing
		needUpdate = true
	}
	if pinger.Status.Dns != pinger.Spec.Dns {
		pinger.Status.Dns = pinger.Spec.Dns
		needUpdate = true
	}

	if needUpdate {
		r.Log.Info("updating pinger status", "pinger", pinger.Name)
		if err := r.Status().Update(ctx, pinger); err != nil {
			r.Log.Error(err, "failed to update pinger status", "pinger", pinger.Name)
			return err
		}
	}

	return nil
}

func (r *PingerReconciler) needSync(pinger *myv1.Pinger) bool {
	if pinger.DeletionTimestamp != nil {
		// pinger is being deleted
		return false
	}
	if pinger.Status.Image != pinger.Spec.Image ||
		pinger.Status.EnableMetrics != pinger.Spec.EnableMetrics ||
		pinger.Status.Ping != pinger.Spec.Ping ||
		pinger.Status.TcpPing != pinger.Spec.TcpPing ||
		pinger.Status.UdpPing != pinger.Spec.UdpPing ||
		pinger.Status.Dns != pinger.Spec.Dns {
		return true
	}
	return false
}
