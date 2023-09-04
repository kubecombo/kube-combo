# feature

## 1. vpn gw

### 1.1 ssl vpn gw

该功能基于 openvpn 实现，可以通过公网 ip，在个人 电脑，手机客户端直接访问 kube-ovn 自定义 vpc subnet 内部的 pod 以及 switch lb 对应是的 svc endpoint。

### 1.2 ipsec vpn gw

该功能基于 strongSwan 实现，[用于 Site-to-Site 场景](https://github.com/strongswan/strongswan#site-to-site-case) ，推荐使用 IKEv2， IKEv1 安全性较低

strongSwan 的主要包括两个配置

- /etc/swanctl/swanctl.conf
- /etc/hosts

swanctl 配置中的 connection 中的域名解析 在 /etc/hosts 中管理，这两个配置都基于[j2](https://github.com/kolypto/j2cli) 来生成，基于 pod exec 将 vpn gw 依赖的 ipsec connection crd 中的信息保存在 connection.yaml 中。

``` bash

j2 swanctl.conf.j2 data.yaml
j2 hosts.j2 data.yaml

# mv swanctl.conf /etc/swanctl/swanctl.conf
# mv hosts /etc/hosts
```

## 2. LB

### 2.1 haproxy lb

### 2.2 nginx lb
