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
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	myv1 "github.com/kubecombo/kube-combo/api/v1"
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

	// update vpn gw spec
	updates.Inc()
	res, err := r.handleAddOrUpdateIpsecConnection(ctx, req)
	if err != nil {
		r.Log.Error(err, "failed to handle ipsecConn")
	}
	switch res {
	case SyncStateError:
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle ipsecConn, will retry")
		return ctrl.Result{}, errRetry
	case SyncStateErrorNoRetry:
		// TODO:// use longer retry interval and limit the retry times
		updateErrors.Inc()
		r.Log.Error(err, "failed to handle ipsecConn, will not retry")
		return ctrl.Result{}, nil
	}
	return ctrl.Result{}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *IpsecConnReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&myv1.IpsecConn{},
			builder.WithPredicates(
				predicate.NewPredicateFuncs(
					func(object client.Object) bool {
						_, ok := object.(*myv1.IpsecConn)
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

func (r *IpsecConnReconciler) validateIpsecConnection(ipsecConn *myv1.IpsecConn) error {
	if ipsecConn.Spec.IkeVersion != "0" && ipsecConn.Spec.IkeVersion != "1" && ipsecConn.Spec.IkeVersion != "2" {
		err := errors.New("ipsec connection spec ike version is invalid")
		r.Log.Error(err, "ignore invalid ipsec connection")
	}

	if ipsecConn.Spec.Auth != "psk" && ipsecConn.Spec.Auth != "pubkey" {
		err := errors.New("ipsec connection spec auth is invalid")
		r.Log.Error(err, "ignore invalid ipsec connection")
	}

	return nil
}

func labelsForIpsecConnection(conn *myv1.IpsecConn) map[string]string {
	return map[string]string{
		VpnGwLabel: conn.Spec.VpnGw,
	}
}

func (r *IpsecConnReconciler) handleAddOrUpdateIpsecConnection(ctx context.Context, req ctrl.Request) (SyncState, error) {
	// create ipsecConn statefulset
	namespacedName := req.NamespacedName.String()
	r.Log.Info("start handleAddOrUpdateIpsecConnection", "ipsecConn", namespacedName)
	defer r.Log.Info("end handleAddOrUpdateIpsecConnection", "ipsecConn", namespacedName)

	// fetch ipsecConn
	ipsecConn, err := r.getIpsecConnection(ctx, req.NamespacedName)
	if err != nil {
		r.Log.Error(err, "failed to get ipsecConn")
		return SyncStateError, err
	}
	if ipsecConn == nil {
		// ipsecConn is deleted
		// onwner reference will trigger vpn gw update ipsec connections
		return SyncStateSuccess, nil
	}

	// validate ipsecConn spec
	if err := r.validateIpsecConnection(ipsecConn); err != nil {
		r.Log.Error(err, "failed to validate ipsecConn")
		// invalid spec no retry
		return SyncStateErrorNoRetry, err
	}

	// patch lable so that vpn gw can find its ipsec conns
	newConn := ipsecConn.DeepCopy()
	labels := labelsForIpsecConnection(newConn)
	newConn.SetLabels(labels)
	err = r.Patch(context.Background(), newConn, client.MergeFrom(ipsecConn))
	if err != nil {
		r.Log.Error(err, "failed to update the ipsecConn")
		return SyncStateError, err
	}
	return SyncStateSuccess, err
}

func (r *IpsecConnReconciler) getIpsecConnection(ctx context.Context, name types.NamespacedName) (*myv1.IpsecConn, error) {
	var res myv1.IpsecConn
	err := r.Get(ctx, name, &res)
	if apierrors.IsNotFound(err) { // in case of delete, get fails and we need to pass nil to the handler
		return nil, nil
	}
	if err != nil {
		r.Log.Error(err, "failed to get ipsecConn", "ipsecConn", name.String())
		return nil, err
	}
	return &res, nil
}
