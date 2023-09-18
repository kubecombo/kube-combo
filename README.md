# Kube-Combo

![Kube-Combo](/docs/images/kubecombo.png)

Kube-Combo 是一款基于 Pod 来提供各种各样网元能力的编排系统，提供丰富的功能以及良好的可运维性。

## 丰富的功能

如果你发现在 K8S 集群中无法直接使用一些高级的网络功能，比如 IPsec vpn GW，SSL vpn GW，Haproxy，Nginx 等，那么 Kube-Combo 将是你的最佳选择。
借助 K8S CNI 提供的底层能力，可以通过多 POD 负载结合各种各样的成熟的应用，提供高可用且丰富的网元能力。

## 良好的可运维性

Kube-Combo 支持一键安装，帮助用户迅速搭建生产就绪的网络应用。同时内置的丰富的监控指标和 Grafana 面板，可帮助用户建立完善的监控体系。

## 1. Devlop

### 1.1 build

```bash
# controller
make docker-build

# 网元
make docker-build-base
make docker-build-keepalived
make docker-build-ipsec-vpn
make docker-build-ssl-vpn

```

### 1.2 run

#### 1.2.1 基于 kube-ovn cni

``` bash
# 切换到你的 kube-ovn 分支，执行
make release
make kind-init; make kind-install

```

### 1.2.1 安装 cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.1/cert-manager.yaml
kubectl get pods -n cert-manager
kubectl get crd | grep cert-manager.io

```

```bash
# 准备 kustomize 工具
cp /snap/bin/kustomize /root/feat/kube-combo/bin/kustomize

```

``` bash
# 切换到 kube-combo 分支

# load image
make kind-load-image

# install kubecombo crd and controller

make install
make deploy 


```
