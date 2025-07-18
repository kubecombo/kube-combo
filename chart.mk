# Makefile for generating helm chart

## Tool Binaries
JINJA2 ?= $(LOCALBIN)/jinja2/bin/jinja2

.PHONY: jinja2
jinja2: 
	test -s $(LOCALBIN)/jinja2 || \
	pip install --target $(LOCALBIN)/jinja2 jinja2-cli

.PHONY: chart
chart: jinja2 kustomize
	$(JINJA2) ./yamls/Chart.yaml.j2 -D app_version=v$(VERSION) > ./charts/kube-combo/Chart.yaml
	$(JINJA2) ./yamls/values.yaml.j2 ./yamls/values.yaml -D global_images_tag=v$(VERSION) > ./charts/kube-combo/values.yaml
	$(KUSTOMIZE) build config/crd > ./charts/kube-combo/templates/kube-combo-crd.yaml
	$(KUSTOMIZE) build yamls/rbac > ./charts/kube-combo/templates/kube-combo-rbac.yaml
	$(KUSTOMIZE) build yamls/default > ./charts/kube-combo/templates/kube-combo-controller.yaml
	@cat ./yamls/manager/append-nodeSelector.yaml >> ./charts/kube-combo/templates/kube-combo-controller.yaml
	@sed -i "s/^\([[:space:]]*replicas:[[:space:]]*\)'{{\(.*\)}}'/\1{{\2}}/" ./charts/kube-combo/templates/kube-combo-controller.yaml
