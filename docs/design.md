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

## 4. debugger

通过 debugger CRD 维护一（组）pod，专门用于运维，可观察性场景：巡检、提供监控数据、对接监控告警、收集 debug 工具

## 5. pinger

复用 kube-ovn-pinger，通过 pinger CRD 指定其参数，通过 debugger CRD 维护 kube-ovn-pinger Pod 生命周期
