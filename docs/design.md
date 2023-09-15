# Design

轻量：

- 由于网络应用往往需要固定 ip, 使用 StatefulSet 负载
- 基于 annotation 为 StatefulSet Pod 固定 ip 池
- 基于 Pod exec 管理应用配置

不参考 [CCM](https://kubernetes.io/zh-cn/docs/concepts/architecture/cloud-controller/)

在设计上我们不打算参考 ccm 的实现，不接入第三方的 api 接口以及客户端， 我们打算直接基于 pod annotation 编排我们需要的业务逻辑

## 1. vpn gw

vpn gw 包括 ipsec vpn 和 ssl vpn

## 2. ipsec connection

ipsec connection 表示 ipsec site-to-site 之间的连接，单独抽象为一个 crd，在 vpn gw 中基于一个 spec 属性来引用

## 3. keepalived

keepalived 表示一个维护 vip 的 keepalived 服务，单独抽象为一个 crd，在 vpn gw 中基于一个 spec 属性来引用

keepalived 由于 VRRP 的缘故，在一个（vpc）子网中存在一个 id 限额。需要保证在一个子网内不能存在冲突的 id。
为了避免冲突，该 id 不支持指定，基于名字 hash 到 id 值（1-255）来维护。
由于 keepalived 和 子网有对应关系，而（vpc）子网是租户隔离的资源，所以为了便于维护，keepalived 有一个 subnet spec 属性。
所以 keepalived 设计上也是租户隔离的资源，即 namespaced 资源。
