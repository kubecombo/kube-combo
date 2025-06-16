# Makefile for building and pushing Docker images

COMMIT = git-$(shell git rev-parse --short HEAD)
DATE = $(shell date +"%Y-%m-%d_%H:%M:%S")

GOLDFLAGS = -extldflags '-z now' -X github.com/kubecombo/kube-combo/versions.COMMIT=$(COMMIT) -X github.com/kubecombo/kube-combo/versions.VERSION=$(RELEASE_TAG) -X github.com/kubecombo/kube-combo/versions.BUILDDATE=$(DATE)
ifdef DEBUG
GO_BUILD_FLAGS = -ldflags "$(GOLDFLAGS)"
else
GO_BUILD_FLAGS = -trimpath -ldflags "-w -s $(GOLDFLAGS)"
endif

# Base Image
BASE_IMG_BASE ?= ${IMAGE_TAG_BASE}-base
BASE_IMG ?= $(BASE_IMG_BASE):v$(VERSION)

# Image Name
SSL_VPN_IMG_BASE ?= ${IMAGE_TAG_BASE}-openvpn
IPSEC_VPN_IMG_BASE ?= ${IMAGE_TAG_BASE}-strongswan
KEEPALIVED_IMG_BASE ?= ${IMAGE_TAG_BASE}-keepalived

# Full Image URL
IMG ?= $(IMAGE_TAG_BASE)-manager:v$(VERSION)
SSL_VPN_IMG ?= $(SSL_VPN_IMG_BASE):v$(VERSION)
IPSEC_VPN_IMG ?= $(IPSEC_VPN_IMG_BASE):v$(VERSION)
KEEPALIVED_IMG ?= $(KEEPALIVED_IMG_BASE):v$(VERSION)

##@ Build

.PHONY: build-amd
build-amd: manifests generate fmt vet ## Build manager amd64 binary.
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/manager -v ./cmd/manager
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/pinger -v ./cmd/pinger

.PHONY: build-arm
build-arm: manifests generate fmt vet ## Build manager arm64 binary.
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/manager -v ./cmd/manager
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/pinger -v ./cmd/pinger

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
docker-build-all-amd64: docker-build-amd64 docker-build-base-amd64 docker-build-ssl-vpn-amd64 docker-build-ipsec-vpn-amd64 docker-build-keepalived-amd64 ## Build all images for amd64.

.PHONY: docker-build-all-arm64
docker-build-all-arm64: docker-build-arm64 docker-build-base-arm64 docker-build-ssl-vpn-arm64 docker-build-ipsec-vpn-arm64 docker-build-keepalived-arm64 ## Build all images for arm64.

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