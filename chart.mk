# Makefile for generating helm chart

.PHONY: chart
chart: 
	jinja2 ./yamls/Chart.yaml.j2 -D app_version=v$(VERSION) > ./charts/kube-combo/Chart.yaml
	jinja2 ./yamls/values.yaml.j2 ./yamls/values.yaml -D global_images_tag=v$(VERSION) > ./charts/kube-combo/values.yaml
