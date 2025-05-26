# [operator-sdk](https://sdk.operatorframework.io/docs/installation/#install-from-github-release)

```
# install

export ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
export OS=$(uname | awk '{print tolower($0)}')

export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/v1.39.2
curl -LO ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH}

mv /usr/bin/operator-sdk_linux_amd64 /usr/bin/operator-sdk
chmod +x /usr/bin/operator-sdk

```

## 1. code init

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
operator-sdk create api --group vpn-gw --version v1 --kind KeepAlived --resource --controller

# 由于版本升级，需要指定新的 kubebuilder
operator-sdk create api --group vpn-gw --version v1 --kind Debugger --resource --controller --plugins=go.kubebuilder.io/v4
operator-sdk create api --group vpn-gw --version v1 --kind Pinger --resource --controller --plugins=go.kubebuilder.io/v4




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
operator-sdk create webhook --group vpn-gw --version v1 --kind KeepAlived --defaulting --programmatic-validation

# 由于版本升级，需要指定新的 kubebuilder
operator-sdk create webhook --group vpn-gw --version v1 --kind Debugger --defaulting --programmatic-validation --plugins=go.kubebuilder.io/v4
operator-sdk create webhook --group vpn-gw --version v1 --kind Pinger --defaulting --programmatic-validation --plugins=go.kubebuilder.io/v4


```

## 2. build push Docker

``` bash
make docker-build docker-push

# make docker-build
# make docker-push

# build keepalived
make docker-build-keepalived docker-push-keepalived

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
