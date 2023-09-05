# 1. code init

init project

``` bash
# --plugins=go/v4-alpha  mac arm supported

kube-combo operator-sdk init --plugins go/v4-alpha --domain kubecombo.com --owner "kubecombo" --repo github.com/kubecombo/kube-combo

Writing kustomize manifests for you to edit...
Writing scaffold for you to edit...
Get controller runtime:
$ go get sigs.k8s.io/controller-runtime@v0.14.1
Update dependencies:
$ go mod tidy
Next: define a resource with:
$ operator-sdk create api

```

create api

``` bash
# we use a domain of kubecombo.com
# so all named API groups will be <group name>.kube-combo.com

# operator-sdk create api
operator-sdk create api --group vpn-gw --version v1 --kind VpnGw --resource --controller
operator-sdk create api --group vpn-gw --version v1 --kind IpsecConn --resource --controller

# 更新依赖
go mod tidy

# 生成 crd 客户端代码
make generate

## 下一步就是编写 crd
## 重新生成代码
## 编写 reconcile 逻辑

### 最后就是生成部署文件
make manifests

```

init webhook

```bash
# operator-sdk create webhook

operator-sdk create webhook --group vpn-gw --version v1 --kind VpnGw --defaulting --programmatic-validation
operator-sdk create webhook --group vpn-gw --version v1 --kind IpsecConn --defaulting --programmatic-validation

```

## 1. build push

Docker

``` bash
make docker-build docker-push

# make docker-build 
# make docker-push

# build openvpn image

make docker-build-ssl-vpn docker-push-ssl-vpn

# build ipsec image
make docker-build-ipsec-vpn docker-push-ipsec-vpn

```

OLM

``` bash
make bundle bundle-build bundle-push

# make bundle
# make bundle-build
# make bundle-push

## 目前不支持直接测试，必须要先把 bundle 传到 registry，有 issue 记录: https://github.com/operator-framework/operator-sdk/issues/6432


```
