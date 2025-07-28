# Makefile for generating helm chart

HELM_GLOBAL_MANIFESTSPATH=/etc/kubernetes/manifests
HELM_GLOBAL_REGISTRY_ADDRESS=docker.io/icoy
HELM_GLOBAL_IMAGES_KUBECOMBO_REPOSITORY=kube-combo-controller
HELM_GLOBAL_IMAGES_OPENVPN_REPOSITORY=kube-combo-openvpn
HELM_GLOBAL_IMAGES_STRONGSWAN_REPOSITORY=kube-combo-strongswan
HELM_KUBEBUILDER_REGISTRY_ADDRESS=gcr.io/kubebuilder
HELM_KUBEBUILDER_IMAGES_REPOSITORY=kube-rbac-proxy
HELM_KUBEBUILDER_IMAGES_TAG=v0.13.1
HELM_MASTER_NODES_LABEL=""
HELM_SSLVPN_NODES_LABEL=""
HELM_IPSECVPN_NODES_LABEL=""

.PHONY: print-helm-vars

print-helm-vars:
	@$(foreach V,$(.VARIABLES), \
		$(if $(and $(filter HELM_%,$(V)), \
			$(filter-out environment% default automatic, $(origin $V))), \
			$(info $(subst HELM_,,$(V)) : $($(V))) \
		))
	@true

## Tool Binaries
JINJA2 ?= $(LOCALBIN)/jinja2/bin/jinja2

.PHONY: jinja2
jinja2: 
	test -s $(LOCALBIN)/jinja2 || \
	pip install --target $(LOCALBIN)/jinja2 jinja2-cli

.PHONY: rsync
rsync: manifests
	rsync -av --exclude='kustomization.yaml' config/default/ yamls/default/
	rsync -av --exclude='kustomization.yaml' config/manager/ yamls/manager/

.PHONY: chart
chart: jinja2 rsync kustomize
	$(JINJA2) ./yamls/Chart.yaml.j2 -D APP_VERSION=v$(VERSION) > ./charts/kube-combo/Chart.yaml
	$(JINJA2) ./yamls/values.yaml.j2 ./yamls/values.yaml -D GLOBAL_IMAGES_TAG=v$(VERSION) > ./charts/kube-combo/values.yaml
	$(KUSTOMIZE) build config/crd > ./charts/kube-combo/templates/kube-combo-crd.yaml
	$(KUSTOMIZE) build yamls/rbac > ./charts/kube-combo/templates/kube-combo-rbac.yaml
	$(KUSTOMIZE) build yamls/default > ./charts/kube-combo/templates/kube-combo-controller.yaml
	@cat ./yamls/manager/append-nodeSelector.yaml >> ./charts/kube-combo/templates/kube-combo-controller.yaml
	@sed -i "s/^\([[:space:]]*replicas:[[:space:]]*\)'{{\(.*\)}}'/\1{{\2}}/" ./charts/kube-combo/templates/kube-combo-controller.yaml
