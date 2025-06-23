# kube-ovn kind env

KIND_CLUSTER_NAME ?= kube-ovn
define docker_ensure_image_exists
	if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep "^$(1)$$" >/dev/null; then \
		docker pull "$(1)"; \
	fi
endef

define kind_load_image
	@if [ "x$(3)" = "x1" ]; then \
		$(call docker_ensure_image_exists,$(2)); \
	fi
	kind load docker-image --name $(1) $(2)
endef

define crictl_pull_image
	crictl pull $(1)
endef

.PHONY: kind-load-image
kind-load-image:
	# $(call kind_load_image,$(KIND_CLUSTER_NAME),$(KUBE_RBAC_PROXY))
	# $(call kind_load_image,$(KIND_CLUSTER_NAME),$(BASE_IMG))
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(IMG))
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(SSL_VPN_IMG))
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(IPSEC_VPN_IMG))
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(KEEPALIVED_IMG))
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(NETSHOOT_IMG))

.PHONY: crictl-pull-image
crictl-pull-image:
	# $(call crictl_pull_image,$(KUBE_RBAC_PROXY))
	# $(call crictl_pull_image,$(BASE_IMG))
	$(call crictl_pull_image,$(IMG))
	$(call crictl_pull_image,$(SSL_VPN_IMG))
	$(call crictl_pull_image,$(IPSEC_VPN_IMG))
	$(call crictl_pull_image,$(KEEPALIVED_IMG))
	$(call crictl_pull_image,$(NETSHOOT_IMG))

.PHONY: reload
reload: kind-load-image
	kubectl delete po -n kube-system -l control-plane=kubecombo-controller-manager

.PHONY: kidr
kidr: kind-load-image install deploy reload
