# 独立测试 Keepalived 的功能

## 1. 创建 vpc subnet

进入 01-ns 目录执行 ./init

## 2. 创建 Keepalived

进入 02-keepalived 目录执行 ./init

## 3. 测试 vip 漂移

由于 Keepalived 主备 pod 是基于 两副本 sts 来维护的, 所以进入 pod-0 可以看到 vip，删除 pod-1，可以看到 vip 漂移至 pod-1

```bash
(.venv) root@empty:~# k exec -it -n ns1                 keepalived01-0 -- bash
root@keepalived01-0:/#
root@keepalived01-0:/#
root@keepalived01-0:/# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
71: eth0@if72: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default
    link/ether 00:00:00:7c:69:57 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.1.0.12/24 brd 10.1.0.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet 10.1.0.2/32 scope global eth0 # 一开始在 pod0
       valid_lft forever preferred_lft forever
    inet6 fe80::200:ff:fe7c:6957/64 scope link
       valid_lft forever preferred_lft forever
root@keepalived01-0:/#
exit
(.venv) root@empty:~# k delete po -n ns1                 keepalived01-0
pod "keepalived01-0" deleted
(.venv) root@empty:~# k exec -it -n ns1                 keepalived01-0 -- bash
root@keepalived01-0:/# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
73: eth0@if74: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default
    link/ether 00:00:00:7c:69:57 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.1.0.12/24 brd 10.1.0.255 scope global eth0 # 重建过程中已漂移至 pod-1
       valid_lft forever preferred_lft forever
    inet6 fe80::200:ff:fe7c:6957/64 scope link
       valid_lft forever preferred_lft forever
root@keepalived01-0:/#



# 可以看到在 pod-1

(.venv) root@empty:~/feat/kube-combo/dist/e2e/keepalived/02-keepalived# k exec -it -n ns1                 keepalived01-1 -- bash
root@keepalived01-1:/# ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
30: eth0@if31: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP group default
    link/ether 00:00:00:c5:87:59 brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 10.1.0.13/24 brd 10.1.0.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet 10.1.0.2/32 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::200:ff:fec5:8759/64 scope link
       valid_lft forever preferred_lft forever
root@keepalived01-1:/#


```
