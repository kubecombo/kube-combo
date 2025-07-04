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
KUBE_OVN_BASE_IMG ?= kubeovn/kube-ovn-base:v1.12.9-mc

# Image Name
SSL_VPN_IMG_BASE ?= ${IMAGE_TAG_BASE}-openvpn
IPSEC_VPN_IMG_BASE ?= ${IMAGE_TAG_BASE}-strongswan
KEEPALIVED_IMG_BASE ?= ${IMAGE_TAG_BASE}-keepalived
DEBUGGER_IMG_BASE ?= ${IMAGE_TAG_BASE}-debugger

# Full Image URL
IMG ?= $(IMAGE_TAG_BASE)-controller:v$(VERSION)
SSL_VPN_IMG ?= $(SSL_VPN_IMG_BASE):v$(VERSION)
IPSEC_VPN_IMG ?= $(IPSEC_VPN_IMG_BASE):v$(VERSION)
KEEPALIVED_IMG ?= $(KEEPALIVED_IMG_BASE):v$(VERSION)
DEBUGGER_IMG ?= $(DEBUGGER_IMG_BASE):v$(VERSION)

##@ go build
.PHONY: go-build-amd
go-build-amd: manifests generate fmt vet ## Build the kube-combo binary for amd64 architecture
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o ./bin/kube-combo-cmd -v ./cmd/

.PHONY: go-build-arm
go-build-arm: manifests generate fmt vet ## Build the kube-combo binary for arm64 architecture
	go mod tidy
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(GO_BUILD_FLAGS) -buildmode=pie -o ./bin/kube-combo-cmd -v ./cmd/

##@ docker build
.PHONY: docker-build-amd64
docker-build-amd64: go-build-amd ## Build docker kube-combo image for amd64.
	docker buildx build --network host --load --platform linux/amd64 -t ${IMG} .

.PHONY: docker-build-arm64
docker-build-arm64: go-build-arm ## Build docker kube-combo image for arm64.
	docker buildx build --network host --load --platform linux/arm64 -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker kube-combo image.
	docker push ${IMG}

.PHONY: docker-build-base-amd64
docker-build-base-amd64: ## Build docker kube-combo-base image for amd64.
	docker buildx build --network host --load --platform linux/amd64 --build-arg ARCH=amd64 -f ./dist/Dockerfile.base -t ${BASE_IMG} .

.PHONY: docker-build-base-arm64
docker-build-base-arm64: ## Build docker kube-combo-base image for arm64.
	docker buildx build --network host --load --platform linux/arm64 --build-arg ARCH=arm64 -f ./dist/Dockerfile.base -t ${BASE_IMG} .

.PHONY: docker-push-base
docker-push-base: ## Push docker kube-combo image.
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

.PHONY: docker-build-debugger-amd64
docker-build-debugger-amd64: ## Build docker debugger image for amd64.
	docker buildx build --network host --load --platform linux/amd64 -f ./dist/Dockerfile.debugger -t ${DEBUGGER_IMG} --build-arg BASE_TAG=v${VERSION} .

.PHONY: docker-build-debugger-arm64
docker-build-debugger-arm64: ## Build docker debugger image for arm64.
	docker buildx build --network host --load --platform linux/arm64 -f ./dist/Dockerfile.debugger -t ${DEBUGGER_IMG} --build-arg BASE_TAG=v${VERSION} .

.PHONY: docker-push-debugger
docker-push-debugger: ## Push docker debugger image
	docker push ${DEBUGGER_IMG}

.PHONY: docker-pull-base-amd64
docker-pull-base-amd64:
	docker pull --platform linux/amd64 ${KUBE_OVN_BASE_IMG}

.PHONY: docker-pull-base-arm64
docker-pull-base-arm64:
	docker pull --platform linux/arm64 ${KUBE_OVN_BASE_IMG}

.PHONY: docker-build-all-amd64
docker-build-all-amd64: docker-build-amd64 docker-build-base-amd64 docker-build-ssl-vpn-amd64 docker-build-ipsec-vpn-amd64 docker-build-keepalived-amd64

.PHONY: docker-build-all-arm64
docker-build-all-arm64: docker-build-arm64 docker-build-base-arm64 docker-build-ssl-vpn-arm64 docker-build-ipsec-vpn-arm64 docker-build-keepalived-arm64

.PHONY: docker-push-all
docker-push-all:
	docker pull ${IMG} && \
	docker push ${SSL_VPN_IMG} && \
	docker push ${IPSEC_VPN_IMG} && \
	docker push ${KEEPALIVED_IMG} && \
	docker push ${DEBUGGER_IMG}

.PHONY: docker-pull-all
docker-pull-all:
	docker pull ${IMG} && \
	docker pull ${SSL_VPN_IMG} && \
	docker pull ${IPSEC_VPN_IMG} && \
	docker pull ${KEEPALIVED_IMG} && \
	docker pull ${DEBUGGER_IMG}

##@ run

.PHONY: run-controller
run-controller: manifests generate fmt vet install ## Run kube-combo controller from your host.
	go mod tidy
	go run ./run/controller/main.go

.PHONY: run-pinger
run-pinger: manifests generate fmt vet ## Run kube-combo pinger from your host.
	go mod tidy
	go run ./run/pinger/main.go