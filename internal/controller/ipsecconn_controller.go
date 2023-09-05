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

	"github.com/go-logr/logr"
	vpngwv1 "github.com/kubecombo/kube-combo/api/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
)

const (
	VpnGwLabel = "vpn-gw"
)

// IpsecConnReconciler reconciles a IpsecConn object
type IpsecConnReconciler struct {
	client.Client
	Scheme    *runtime.Scheme
	Log       logr.Logger
	Namespace string
	Reload    chan event.GenericEvent
}

//+kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=ipsecconns,verbs=get;list;watch;create;update;patch;delete
//+kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=ipsecconns/status,verbs=get;update;patch
//+kubebuilder:rbac:groups=vpn-gw.kubecombo.com,resources=ipsecconns/finalizers,verbs=update

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
// TODO(user): Modify the Reconcile function to compare the state specified by
// the IpsecConn object against the actual cluster state, and then
// perform operations to make the cluster state reflect the state specified by
// the user.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.14.1/pkg/reconcile
func (r *IpsecConnReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	_ = log.FromContext(ctx)

	// TODO(user): your logic here
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start reconcile", "ipsecConn", namespacedName)
	defer r.Log.Info("end reconcile", "ipsecConn", namespacedName)
	updates.Inc()
	// fetch ipsecConn
	ipsecConn, err := r.getIpsecConnection(ctx, req.NamespacedName)
	if err != nil {
		r.Log.Error(err, "failed to get ipsecConn")
		return ctrl.Result{}, err
	}
	if ipsecConn == nil {
		// ipsecConn is deleted
		// onwner reference will trigger vpn gw update ipsec connections
		return ctrl.Result{}, nil
	}
	// update vpn gw spec
	res, err := r.handleAddOrUpdateIpsecConnection(req, ipsecConn)
	switch res {
	case SyncStateError:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle ipsecConn")
		return ctrl.Result{}, errRetry
	case SyncStateErrorNoRetry:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle ipsecConn")
		return ctrl.Result{}, nil
	}

	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *IpsecConnReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&vpngwv1.IpsecConn{},
			builder.WithPredicates(
				predicate.NewPredicateFuncs(
					func(object client.Object) bool {
						_, ok := object.(*vpngwv1.IpsecConn)
						if !ok {
							err := errors.New("invalid ipsecConn")
							r.Log.Error(err, "expected ipsecConn in worequeue but got something else")
							return false
						}
						return true
					},
				),
			),
		).
		Complete(r)
}

func (r *IpsecConnReconciler) validateIpsecConnection(ipsecConn *vpngwv1.IpsecConn, namespacedName string) error {
	if ipsecConn.Spec.VpnGw == "" {
		err := fmt.Errorf("ipsecConn vpn gw is required")
		r.Log.Error(err, "should set vpn gw")
		return err
	}

	if ipsecConn.Spec.IkeVersion != "0" && ipsecConn.Spec.IkeVersion != "1" && ipsecConn.Spec.IkeVersion != "2" {
		err := fmt.Errorf("ipsec connection spec ike version is invalid, ike version spec: %s", ipsecConn.Spec.IkeVersion)
		r.Log.Error(err, "ignore invalid ipsec connection")
	}

	if ipsecConn.Spec.Auth != "psk" && ipsecConn.Spec.Auth != "pubkey" {
		err := fmt.Errorf("ipsec connection spec auth is invalid, auth spec: %s", ipsecConn.Spec.Auth)
		r.Log.Error(err, "ignore invalid ipsec connection")
	}

	if ipsecConn.Spec.RemotePublicIp == "" {
		err := fmt.Errorf("ipsecConn remote public ip is required")
		r.Log.Error(err, "should set remote public ip")
		return err
	}

	if ipsecConn.Spec.RemotePrivateCidrs == "" {
		err := fmt.Errorf("ipsecConn remote private cidrs is required")
		r.Log.Error(err, "should set remote private cidrs")
		return err
	}

	if ipsecConn.Spec.LocalPrivateCidrs == "" {
		err := fmt.Errorf("ipsecConn local private cidrs is required")
		r.Log.Error(err, "should set local private cidrs")
		return err
	}

	return nil
}

func labelsForIpsecConnection(conn *vpngwv1.IpsecConn) map[string]string {
	return map[string]string{
		VpnGwLabel: conn.Spec.VpnGw,
	}
}

func (r *IpsecConnReconciler) handleAddOrUpdateIpsecConnection(req ctrl.Request, ipsecConn *vpngwv1.IpsecConn) (SyncState, error) {
	// create ipsecConn statefulset
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start handleAddOrUpdateIpsecConnection", "ipsecConn", namespacedName)
	defer r.Log.Info("end handleAddOrUpdateIpsecConnection", "ipsecConn", namespacedName)

	// validate ipsecConn spec
	if err := r.validateIpsecConnection(ipsecConn, namespacedName); err != nil {
		r.Log.Error(err, "failed to validate ipsecConn")
		// invalid spec no retry
		return SyncStateErrorNoRetry, err
	}

	// patch lable so that vpn gw can find its ipsec conns
	newConn := ipsecConn.DeepCopy()
	labels := labelsForIpsecConnection(newConn)
	newConn.SetLabels(labels)
	err := r.Patch(context.Background(), newConn, client.MergeFrom(ipsecConn))
	if err != nil {
		r.Log.Error(err, "failed to update the ipsecConn")
		return SyncStateError, err
	}
	return SyncStateSuccess, err
}

func (r *IpsecConnReconciler) getIpsecConnection(ctx context.Context, name types.NamespacedName) (*vpngwv1.IpsecConn, error) {
	var res vpngwv1.IpsecConn
	err := r.Get(ctx, name, &res)
	if apierrors.IsNotFound(err) { // in case of delete, get fails and we need to pass nil to the handler
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &res, nil
}
