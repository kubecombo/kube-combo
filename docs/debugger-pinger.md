# Debugger Pinger

## 1. UML

```mermaid
---
title: Debugger Pinger CRD
---
classDiagram
    note for Debugger "Debugger with(out) Pinger"
    Debugger <|-- Pinger
    Debugger <|-- ConfigMap
    note for Pinger "tcpping udpping ping nslookup tasks"
    Debugger <|-- Pod
    Debugger <|-- DaemonSet

    class Debugger {
        String WorkloadType
        String CPU
        String Memory
        String QoSBandwidth
        String Subnet
        Bool HostNetwork
        String Image
        Map Selector
        Map Tolerations
        Map Affinity
        String NodeName
        Bool EnablePinger
        String Pinger "pinger name"
        Bool EnableConfigMap
        String ConfigMap "cm name"
        Bool HostCheckList "host run check list"

        Reconcile()
        GetDebugger()
        IsChange()
        GetPinger()
        HandlerAddOrUpdatePod()
        HandlerAddOrUpdateDaemonset()
        Update()
    }

   class ConfigMap {
        String Name
        String Namespace
        String Data "script content"
   }

   class Pinger {
        String Image
        Bool EnableMetrics
        String Ping
        String TcpPing
        String UdpPing
        String Dns

        Reconcile()
        GetPinger()
        IsChange()
        Update()
    }

   class Pod {
        Bool Hostnetwork
        String NodeName

        Create()
        Delete()
    }

   class DaemonSet {
     Bool Hostnetwork
     Map Selector
     Map Tolerations
     Map Affinity

     Create()
     Delete()
    }
```

Debugger CRD:

1. 控制 pod 的生命周期
2. 至少提供一个 pod 用于执行脚本：巡检，定位等

Pinger CRD：

1. 持久化维护 ping 测任务：`ping`  `udp`  `tcp`  `nslookup`
2. 可以选择是否启用 metrics

任务如果执行失败，会以 event 的形式记录到 pod

如果没有 Pinger，Debugger 只会启动一个容器

## 2. Sequence

```mermaid
zenuml
    title Annotators
    @Control kubecombo
    @Database DebuggerCRD
    @Database PingerCRD
    @Database Pod

    par {
        kubecombo->DebuggerCRD: get the debugger?
        kubecombo->PingerCRD: get the pinger of debugger spec?
        kubecombo->Pod: create | update | delete pod
    }
```

## 3. topo

ping gw

```mermaid
block-beta
columns 1
  block:ID
  A(("Pod1 on node1"))
  B(("Pod2 on node2"))
  C(("Pod3 on node3"))
  end
  space
  Switch
  A --"ping"--> Switch
  B --"ping"--> Switch
  C --"ping"--> Switch


```

默认统一 daemonset 内的 pinger 启动后，不同 node 上的 pod 都会进行互相 ping 测，到交换机网关则需要在 pinger spec 中指定网关 ip，而且 pod 本身启动时 kube-ovn-cni 会自动检测 ping 网关。
