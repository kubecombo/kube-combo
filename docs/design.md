# Design

轻量：

- 由于网络应用往往需要固定 ip, 使用 StatefulSet 负载
- 基于 annotation 为 StatefulSet Pod 固定 ip 池
- 基于 Pod exec 管理应用配置

## 1. 不参考 [CCM](https://kubernetes.io/zh-cn/docs/concepts/architecture/cloud-controller/)

在设计上我们不打算参考 ccm 的实现，不接入第三方的 api 接口以及客户端， 我们打算直接基于 pod annotation 编排我们需要的业务逻辑
