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
PINGER_IMG ?= $(IMAGE_TAG_BASE)-pinger:v$(VERSION)
SSL_VPN_IMG ?= $(SSL_VPN_IMG_BASE):v$(VERSION)
IPSEC_VPN_IMG ?= $(IPSEC_VPN_IMG_BASE):v$(VERSION)
KEEPALIVED_IMG ?= $(KEEPALIVED_IMG_BASE):v$(VERSION)

##@ Build
.PHONY: go-build-all-amd
go-build-all-amd: manifests generate fmt vet
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/manager -v ./cmd/manager
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/pinger -v ./cmd/pinger

.PHONY: go-build-all-arm
go-build-all-arm: manifests generate fmt vet
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/manager -v ./cmd/manager
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/pinger -v ./cmd/pinger

.PHONY: go-build-pinger-amd
go-build-pinger-amd: manifests generate fmt vet
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/pinger -v ./cmd/pinger

.PHONY: go-build-pinger-arm
go-build-pinger-arm: manifests generate fmt vet
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/pinger -v ./cmd/pinger

.PHONY: go-build-manager-amd
go-build-manager-amd: manifests generate fmt vet
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/manager -v ./cmd/manager

.PHONY: go-build-manager-arm
go-build-manager-arm: manifests generate fmt vet
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o bin/manager -v ./cmd/manager

.PHONY: docker-build-manager-amd64
docker-build-manager-amd64: test build-amd64
	docker buildx build --network host --load --platform linux/amd64 -t ${IMG} .

.PHONY: docker-build-manager-arm64
docker-build-manager-arm64: test build-arm64
	docker buildx build --network host --load --platform linux/arm64 -t ${IMG} .

.PHONY: docker-push-manager
docker-push-manager:
	docker push ${IMG}

.PHONY: docker-build-pinger-amd64
docker-build-pinger-amd64:
	docker buildx build --network host --load --platform linux/amd64 -t ${PINGER_IMG} ./Dockerfile.pinger

.PHONY: docker-build-pinger-arm64
docker-build-pinger-arm64:
	docker buildx build --network host --load --platform linux/arm64 -t ${PINGER_IMG} ./Dockerfile.pinger

.PHONY: docker-push-pinger
docker-push-pinger:
	docker push ${PINGER_IMG}

.PHONY: docker-build-base-amd64
docker-build-base-amd64:
	docker buildx build --network host --load --platform linux/amd64 -f ./dist/Dockerfile.base -t ${BASE_IMG} .

.PHONY: docker-build-base-arm64
docker-build-base-arm64:
	docker buildx build --network host --load --platform linux/arm64 -f ./dist/Dockerfile.base -t ${BASE_IMG} .

.PHONY: docker-push-base
docker-push-base:
	docker push ${BASE_IMG}

.PHONY: docker-pull-base
docker-pull-base:
	docker pull ${BASE_IMG}

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
docker-build-all-amd64: docker-build-manager-amd64 docker-build-pinger-amd64 docker-build-base-amd64 docker-build-ssl-vpn-amd64 docker-build-ipsec-vpn-amd64 docker-build-keepalived-amd64

.PHONY: docker-build-all-arm64
docker-build-all-arm64: docker-build-manager-arm64 docker-build-pinger-arm64 docker-build-base-arm64 docker-build-ssl-vpn-arm64 docker-build-ipsec-vpn-arm64 docker-build-keepalived-arm64

.PHONY: docker-push-all
docker-push-all:
	docker pull ${IMG} && \
	docker push ${PINGER_IMG} && \
	docker push ${SSL_VPN_IMG} && \
	docker push ${IPSEC_VPN_IMG} && \
	docker push ${KEEPALIVED_IMG}

.PHONY: docker-pull-all
docker-pull-all:
	docker pull ${IMG} && \
	docker pull ${PINGER_IMG} && \
	docker pull ${SSL_VPN_IMG} && \
	docker pull ${IPSEC_VPN_IMG} && \
	docker pull ${KEEPALIVED_IMG}
