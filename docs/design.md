# Design

轻量：

- 由于网络应用往往需要固定 ip, 使用 StatefulSet 负载
- 基于 annotation 为 StatefulSet Pod 固定 ip 池
- 基于 Pod exec 管理应用配置
