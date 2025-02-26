# 维护

前置依赖

- k8s
- cert-manager
- cni(kube-ovn)

```bash

# 基于 kube-ovn kind 部署，一键拉起 certmanager
make kind-init-ha; make kind-install-webhook; make ovn-vpc-nat-gw-conformance-e2e

```

提供多种方式部署：

- 可以基于 helm 部署
- 可以基于 make deploy 部署
- 可以基于 kubectl apply 部署

## 1. install

目前认为 olm 本身不够成熟，基于 `make deploy` 来部署

```bash

cd config/manager && /root/kube-combo/bin/kustomize edit set image controller=registry.cn-hangzhou.aliyuncs.com/bobz/kube-combo:latest
/root/kube-combo/bin/kustomize build config/default | kubectl apply -f -


```

[operator-sdk 二进制安装方式](https://sdk.operatorframework.io/docs/installation/)

```bash
# 在 k8s集群安装该项目
operator-sdk olm install

## ref https://github.com/operator-framework/operator-lifecycle-manager/releases/tag/v0.24.0

curl -L https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.24.0/install.sh -o install.sh
chmod +x install.sh
./install.sh v0.24.0


# 运行 operator

operator-sdk run bundle kube-combo-bundle:888

# 检查 operator 已安装

kubectl get csv

## 基于 kubectl apply 运行一个该 operator 维护的 crd

# 清理该 operator
k get operator

operator-sdk cleanup vpn-gw

```

### 4. certmanager

```bash
operator-sdk olm install

# 功能上 operator-sdk == kubectl operator

kubectl krew install operator
kubectl create ns cert-manager
kubectl operator install cert-manager -n cert-manager --channel candidate --approval Automatic --create-operator-group

# kubectl operator install cert-manager -n operators --channel stable --approval Automatic

kubectl get events -w -n operators

kubectl operator list
kubectl operator uninstall cert-manager -n cert-manager

# 目前认为最好是基于 kubectl apply 安装最新的 v1.13.2

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml
kubectl get pods -n cert-manager
kubectl get crd | grep cert-manager.io

# 清理: https://cert-manager.io/docs/installation/kubectl/


```
