# Makefile for generating helm chart

.PHONY: chart
chart: 
	jinja2 ./yamls/Chart.yaml.j2 -D app_version=v$(VERSION) > ./charts/kube-combo/Chart.yaml
	jinja2 ./yamls/values.yaml.j2 ./yamls/values.yaml -D global_images_tag=v$(VERSION) > ./charts/kube-combo/values.yaml
	$(KUSTOMIZE) build config/crd > ./charts/kube-combo/templates/kube-combo-crd.yaml
	$(KUSTOMIZE) build config/rbac > ./charts/kube-combo/templates/kube-combo-rbac.yaml