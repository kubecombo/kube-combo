# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=xxx)
# - use environment variables to overwrite this value (e.g export VERSION=xxx)
VERSION ?= 0.0.7

print-version:
	@echo $(VERSION)

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "candidate,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=candidate,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="candidate,fast,stable")
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# kubecombo.com/kube-combo-bundle:$VERSION and kubecombo.com/kube-combo-catalog:$VERSION.
# IMAGE_TAG_BASE ?= kubecombo.com/kube-combo
IMAGE_TAG_BASE ?= icoy/kube-combo

BASE_IMG_BASE ?= ${IMAGE_TAG_BASE}-base
SSL_VPN_IMG_BASE ?= ${IMAGE_TAG_BASE}-openvpn
IPSEC_VPN_IMG_BASE ?= ${IMAGE_TAG_BASE}-strongswan
KEEPALIVED_IMG_BASE ?= ${IMAGE_TAG_BASE}-keepalived

# dependencies
KUBE_RBAC_PROXY ?= gcr.io/kubebuilder/kube-rbac-proxy:v0.15.0
CERT_MANAGER_CAINJECTOR ?= quay.io/jetstack/cert-manager-cainjector:v1.17.0
CERT_MANAGER_CONTROLLER ?= quay.io/jetstack/cert-manager-controller:v1.17.0
CERT_MANAGER_WEBHOOK ?= quay.io/jetstack/cert-manager-webhook:v1.17.0

# netshoot
NETSHOOT_IMG ?= docker.io/nicolaka/netshoot:latest

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG ?= $(IMAGE_TAG_BASE)-bundle:v$(VERSION)

# BUNDLE_GEN_FLAGS are the flags passed to the operator-sdk generate bundle command
BUNDLE_GEN_FLAGS ?= -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)

# USE_IMAGE_DIGESTS defines if images are resolved via tags or digests
# You can enable this value if you would like to use SHA Based Digests
# To enable set flag to true
USE_IMAGE_DIGESTS ?= false
ifeq ($(USE_IMAGE_DIGESTS), true)
	BUNDLE_GEN_FLAGS += --use-image-digests
endif

# Set the Operator SDK version to use. By default, what is installed on the system is used.
# This is useful for CI or a project to utilize a specific version of the operator-sdk toolkit.
OPERATOR_SDK_VERSION ?= v1.31.0

# Image URL to use all building/pushing image targets
# IMG ?= controller:latest
IMG ?= $(IMAGE_TAG_BASE)-controller:v$(VERSION)

BASE_IMG ?= $(BASE_IMG_BASE):v$(VERSION)
SSL_VPN_IMG ?= $(SSL_VPN_IMG_BASE):v$(VERSION)
IPSEC_VPN_IMG ?= $(IPSEC_VPN_IMG_BASE):v$(VERSION)
KEEPALIVED_IMG ?= $(KEEPALIVED_IMG_BASE):v$(VERSION)

# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.26.0

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test ./... -coverprofile cover.out

##@ Build

.PHONY: build-amd64
build-amd64: manifests generate fmt vet ## Build manager amd64 binary.
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o bin/manager cmd/main.go

.PHONY: build-arm64
build-arm64: manifests generate fmt vet ## Build manager arm64 binary.
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -a -o bin/manager cmd/main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./cmd/main.go

# If you wish built the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64 ). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build-amd64
docker-build-amd64: test build-amd64 ## Build docker amd64 image with the manager.
	docker buildx build --network host --load --platform linux/amd64 -t ${IMG} .

.PHONY: docker-build-arm64
docker-build-arm64: test build-arm64 ## Build docker arm64 image with the manager.
	docker buildx build --network host --load --platform linux/arm64 -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	docker push ${IMG}

.PHONY: docker-build-base-amd64
docker-build-base-amd64: ## Build docker base image for amd64.
	docker buildx build --network host --load --platform linux/amd64 -f ./dist/Dockerfile.base -t ${BASE_IMG} .

.PHONY: docker-build-base-arm64
docker-build-base-arm64: ## Build docker base image for arm64.
	docker buildx build --network host --load --platform linux/arm64 -f ./dist/Dockerfile.base -t ${BASE_IMG} .

.PHONY: docker-push-base
docker-push-base: ## Push docker base image
	docker push ${BASE_IMG}

.PHONY: docker-build-ssl-vpn-amd64
docker-build-ssl-vpn-amd64: ## Build docker ssl-vpn image for amd64.
	docker buildx build --network host --load --platform linux/amd64 -f ./dist/Dockerfile.openvpn -t ${SSL_VPN_IMG} --build-arg BASE_TAG=v${VERSION} .

.PHONY: docker-build-ssl-vpn-arm64
docker-build-ssl-vpn-arm64: ## Build docker ssl-vpn image for arm64.
	docker buildx build --network host --load --platform linux/arm64 -f ./dist/Dockerfile.openvpn -t ${SSL_VPN_IMG} --build-arg BASE_TAG=v${VERSION} .

.PHONY: docker-push-ssl-vpn
docker-push-ssl-vpn: ## Push docker ssl-vpn image
	docker push ${SSL_VPN_IMG}

.PHONY: docker-build-ipsec-vpn-amd64
docker-build-ipsec-vpn-amd64: ## Build docker ipsec-vpn image for amd64.
	docker buildx build --network host --load --platform linux/amd64 -f ./dist/Dockerfile.strongSwan -t ${IPSEC_VPN_IMG} --build-arg BASE_TAG=v${VERSION} .

.PHONY: docker-build-ipsec-vpn-arm64
docker-build-ipsec-vpn-arm64: ## Build docker ipsec-vpn image for arm64.
	docker buildx build --network host --load --platform linux/arm64 -f ./dist/Dockerfile.strongSwan -t ${IPSEC_VPN_IMG} --build-arg BASE_TAG=v${VERSION} .

.PHONY: docker-push-ipsec-vpn
docker-push-ipsec-vpn: ## Push docker ipsec-vpn image
	docker push ${IPSEC_VPN_IMG}

.PHONY: docker-build-keepalived-amd64
docker-build-keepalived-amd64: ## Build docker keepalived image for amd64.
	docker buildx build --network host --load --platform linux/amd64 -f ./dist/Dockerfile.keepalived -t ${KEEPALIVED_IMG} --build-arg BASE_TAG=v${VERSION} .

.PHONY: docker-build-keepalived-arm64
docker-build-keepalived-arm64: ## Build docker keepalived image for arm64.
	docker buildx build --network host --load --platform linux/arm64 -f ./dist/Dockerfile.keepalived -t ${KEEPALIVED_IMG} --build-arg BASE_TAG=v${VERSION} .

.PHONY: docker-push-keepalived
docker-push-keepalived: ## Push docker keepalived image
	docker push ${KEEPALIVED_IMG}

.PHONY: docker-build-all-amd64
docker-build-all-amd64: docker-build-amd64 docker-build-base docker-build-ssl-vpn docker-build-ipsec-vpn docker-build-keepalived ## Build all images for amd64.

.PHONY: docker-build-all-arm64
docker-build-all-arm64: docker-build-arm64 docker-build-base-arm docker-build-ssl-vpn-arm docker-build-ipsec-vpn-arm docker-build-keepalived-arm ## Build all images for arm64.

.PHONY: docker-pull-all
docker-pull-all: ## Pull docker images
	docker pull ${BASE_IMG} && \
	docker pull ${IMG} && \
	docker pull ${SSL_VPN_IMG} && \
	docker pull ${IPSEC_VPN_IMG} && \
	docker pull ${KEEPALIVED_IMG}

.PHONY: docker-push-all
docker-push-all: ## Push docker images
	docker push ${BASE_IMG} && \
	docker push ${IMG} && \
	docker push ${SSL_VPN_IMG} && \
	docker push ${IPSEC_VPN_IMG} && \
	docker push ${KEEPALIVED_IMG}

# PLATFORMS defines the target platforms for  the manager image be build to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - able to use docker buildx . More info: https://docs.docker.com/build/buildx/
# - have enable BuildKit, More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image for your registry (i.e. if you do not inform a valid value via IMG=<myregistry/image:<tag>> then the export will fail)
# To properly provided solutions that supports more than one platform you should use this option.

# PLATFORMS ?= linux/arm64,linux/amd64,linux/s390x,linux/ppc64le
# .PHONY: docker-buildx
# docker-buildx: test ## Build and push docker image for the manager for cross-platform support
# 	# copy existing Dockerfile and insert --platform=${BUILDPLATFORM} into Dockerfile.cross, and preserve the original Dockerfile
# 	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' Dockerfile > Dockerfile.cross
# 	- docker buildx create --name project-v3-builder
# 	docker buildx use project-v3-builder
# 	- docker buildx build --push --platform=$(PLATFORMS) --tag ${IMG} -f Dockerfile.cross .
# 	- docker buildx rm project-v3-builder
# 	rm Dockerfile.cross

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest

## Tool Versions
#KUSTOMIZE_VERSION ?= v5.3.0
KUSTOMIZE_VERSION ?= v5.6.0
CONTROLLER_TOOLS_VERSION ?= v0.17.2

KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary. If wrong version is installed, it will be removed before downloading.
$(KUSTOMIZE): $(LOCALBIN)
	@if test -x $(LOCALBIN)/kustomize && ! $(LOCALBIN)/kustomize version | grep -q $(KUSTOMIZE_VERSION); then \
		echo "$(LOCALBIN)/kustomize version is not expected $(KUSTOMIZE_VERSION). Removing it before installing."; \
		rm -rf $(LOCALBIN)/kustomize; \
	fi
	# test -s $(LOCALBIN)/kustomize || { curl -Ss $(KUSTOMIZE_INSTALL_SCRIPT) | bash -s -- $(subst v,,$(KUSTOMIZE_VERSION)) $(LOCALBIN); }

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary. If wrong version is installed, it will be overwritten.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen && $(LOCALBIN)/controller-gen --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	test -s $(LOCALBIN)/setup-envtest || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest

.PHONY: operator-sdk
OPERATOR_SDK ?= $(LOCALBIN)/operator-sdk
operator-sdk: ## Download operator-sdk locally if necessary.
ifeq (,$(wildcard $(OPERATOR_SDK)))
ifeq (, $(shell which operator-sdk 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPERATOR_SDK)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPERATOR_SDK) https://github.com/operator-framework/operator-sdk/releases/download/$(OPERATOR_SDK_VERSION)/operator-sdk_$${OS}_$${ARCH} ;\
	chmod +x $(OPERATOR_SDK) ;\
	}
else
OPERATOR_SDK = $(shell which operator-sdk)
endif
endif

.PHONY: bundle
bundle: manifests kustomize operator-sdk ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS)
	$(OPERATOR_SDK) bundle validate ./bundle

.PHONY: bundle-build
bundle-build: ## Build the bundle image.
	# docker build -f bundle.Dockerfile -t $(BUNDLE_IMG) .
	docker buildx build --load --platform linux/amd64 -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)

.PHONY: opm
OPM = ./bin/opm
opm: ## Download opm locally if necessary.
ifeq (,$(wildcard $(OPM)))
ifeq (,$(shell which opm 2>/dev/null))
	@{ \
	set -e ;\
	mkdir -p $(dir $(OPM)) ;\
	OS=$(shell go env GOOS) && ARCH=$(shell go env GOARCH) && \
	curl -sSLo $(OPM) https://github.com/operator-framework/operator-registry/releases/download/v1.23.0/$${OS}-$${ARCH}-opm ;\
	chmod +x $(OPM) ;\
	}
else
OPM = $(shell which opm)
endif
endif

# A comma-separated list of bundle images (e.g. make catalog-build BUNDLE_IMGS=example.com/operator-bundle:v0.1.0,example.com/operator-bundle:v0.2.0).
# These images MUST exist in a registry and be pull-able.
BUNDLE_IMGS ?= $(BUNDLE_IMG)

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG ?= $(IMAGE_TAG_BASE)-catalog:v$(VERSION)

# Set CATALOG_BASE_IMG to an existing catalog image tag to add $BUNDLE_IMGS to that image.
ifneq ($(origin CATALOG_BASE_IMG), undefined)
FROM_INDEX_OPT := --from-index $(CATALOG_BASE_IMG)
endif

# Build a catalog image by adding bundle images to an empty catalog using the operator package manager tool, 'opm'.
# This recipe invokes 'opm' in 'semver' bundle add mode. For more information on add modes, see:
# https://github.com/operator-framework/community-operators/blob/7f1438c/docs/packaging-operator.md#updating-your-existing-operator
.PHONY: catalog-build
catalog-build: opm ## Build a catalog image.
	$(OPM) index add --container-tool docker --mode semver --tag $(CATALOG_IMG) --bundles $(BUNDLE_IMGS) $(FROM_INDEX_OPT)

# Push the catalog image.
.PHONY: catalog-push
catalog-push: ## Push a catalog image.
	$(MAKE) docker-push IMG=$(CATALOG_IMG)

# Kind install
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
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(KUBE_RBAC_PROXY))
	#$(call kind_load_image,$(KIND_CLUSTER_NAME),$(BASE_IMG))
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(IMG))
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(SSL_VPN_IMG))
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(IPSEC_VPN_IMG))
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(KEEPALIVED_IMG))
	$(call kind_load_image,$(KIND_CLUSTER_NAME),$(NETSHOOT_IMG))

.PHONY: crictl-pull-image
crictl-pull-image:
	#$(call crictl_pull_image,$(KUBE_RBAC_PROXY))
	#$(call crictl_pull_image,$(BASE_IMG))
	$(call crictl_pull_image,$(IMG))
	$(call crictl_pull_image,$(SSL_VPN_IMG))
	$(call crictl_pull_image,$(IPSEC_VPN_IMG))
	$(call crictl_pull_image,$(KEEPALIVED_IMG))
	$(call crictl_pull_image,$(NETSHOOT_IMG))

.PHONY: reload
reload: kind-load-image
	kubectl delete po -n kube-system -l control-plane=controller-manager

.PHONY: kidr
kidr: kind-load-image install deploy reload
