# Makefile for generating helm chart

.PHONY: chart
chart: 
	jinja2 ./yamls/Chart.yaml.j2 -D app_version=v$(VERSION) > ./charts/kube-combo/Chart.yaml
	jinja2 ./yamls/values.yaml.j2 ./yamls/values.yaml -D global_images_tag=v$(VERSION) > ./charts/kube-combo/values.yaml
	$(KUSTOMIZE) build config/crd > ./charts/kube-combo/templates/kube-combo-crd.yaml
	$(KUSTOMIZE) build yamls/rbac > ./charts/kube-combo/templates/kube-combo-rbac.yaml
	$(KUSTOMIZE) build yamls/default > ./charts/kube-combo/templates/kube-combo-controller.yaml
	@cat ./yamls/manager/append-nodeSelector.yaml >> ./charts/kube-combo/templates/kube-combo-controller.yaml
	@sed -i "s/^\([[:space:]]*replicas:[[:space:]]*\)'{{\(.*\)}}'/\1{{\2}}/" ./charts/kube-combo/templates/kube-combo-controller.yaml