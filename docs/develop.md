# 1. code init

``` bash

operator-sdk init --domain kube-combo.com --repo github.com/kubecombo/kube-combo --plugins=go/v4-alpha

# we'll use a domain of kube-combo.com
# so all API groups will be <group>.kube-combo.com

# --plugins=go/v4-alpha  mac arm 芯片需要指定

# 该步骤后可创建 api
# operator-sdk create api
operator-sdk create api --group vpn-gw --version v1 --kind VpnGw --resource --controller
operator-sdk create api --group vpn-gw --version v1 --kind IpsecConn --resource --controller


#  make generate   生成controller 相关的 informer clientset 等代码
 
## 下一步就是编写crd
## 重新生成代码
## 编写 reconcile 逻辑

### 最后就是生成部署文件
make manifests

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
