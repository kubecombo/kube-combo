# design

refer kolla-ansible/ansible/roles/loadbalancer/templates/keepalived/

## VRRP

VRRP 协议使用多播数据来传输 VRRP 数据，VRRP 数据使用特殊的虚拟源 MAC 地址发送数据而不是自身网卡的 MAC 地址，VRRP 运行时只有 MASTER 路由器定时发送 VRRP 通告信息，表示 MASTER 工作正常以及虚拟路由器IP(组)，BACKUP只接收VRRP 数据，不发送数据，如果一定时间内没有接收到 MASTER 的通告信息，各 BACKUP 将宣告自己成为 MASTER，发送通告信息，重新进行MASTER选举状态。

配置 VRRP 协议时需要配置每个路由器的虚拟路由器 ID(VRID)和优先权值，使用 VRID 将路由器进行分组，具有相同 VRID 值的路由器为同一个组，VRID 是一个 0～255 的正整数；
同一组中的路由器通过使用优先权值来选举 MASTER，优先权大者为MASTER，优先权也是一个 0～255 的正整数。

### VRRP ID 的维护

同一个子网中的最多有 0-255 个 可分配 VRRP ID

子网 -- VRRP ID -- keepalived(所属资源名)

需要基于 CRD 建立一个维护关系， 防止出现冲突

由于该资源是维护子网内的 keepalived vrrp id 的占用，所以还是打算使用 subnet 作为资源名
subnet

属性：
vrrp id：资源名
1: "ns1.vpngw1"
2: "ns1.vpngw1"
3: "ns2.halb"

### VRRP 使用单播还是多播

openstack 默认使用多播，而且[单播功能比较弱](https://serverfault.com/questions/615727/keepalived-multicast-vs-unicast)
Q1. 我想知道多个 VRRP 路由器是否会用多播广告淹没网络并导致一些性能问题？在这种情况下您会建议使用单播吗？

任何数量的 VRRP 路由器都不会导致任何问题，即使每秒都会发出通告，也只是一个广播数据包。我不建议使用单播，因为它使 VRRP 设置比应有的更脆弱，每次需要重新配置对等点 IP 地址时，您都需要更新其他对等点的配置，可能会导致停机。

### 安全配置

目前暂不使用任何身份验证
从安全角度来看，PASS 身份验证毫无用处，IPSEC-AH 是唯一的安全身份验证类型

### 实现

keepalived 由于 VRRP 的缘故，在一个（vpc）子网中存在一个 id 限额。需要保证在一个子网内不能存在冲突的 id。
为了避免冲突，该 id 不支持指定，基于名字 hash 到 id 值（1-255）来维护。
由于 keepalived 和 子网有对应关系，而（vpc）子网是租户隔离的资源，所以为了便于维护，keepalived 有一个 subnet spec 属性。
所以 keepalived 设计上也是租户隔离的资源，即 namespaced 资源。

实现上简单参考了下 [keepalive-operator](https://wangzheng422.github.io/docker_env/ocp4/4.7/4.7.keepalived.operator.html),
它是面向集群的，但是我们想实现一个面向租户隔离的（namespaced）子网的 keepalived。
