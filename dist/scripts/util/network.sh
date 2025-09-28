#!/bin/bash

# 获取所有的bond网卡
# 使用方法：get_bond_interfaces
get_bond_interfaces() {
    local result

    if [ ! -d /proc/net/bonding ]; then
        echo "/proc/net/bonding not exists"
        return 1
    fi

    result=$(find /proc/net/bonding/ -maxdepth 1 -mindepth 1 -printf "%f\n" | sort -u)
    local ret=$?

    if [ $ret -ne 0 ]; then
        echo "Failed to list bond interfaces"
        return $ret
    fi

    echo "$result"
    return 0
}

# 获取bond网卡所有的子接口
# 使用方法：get_bond_subinterfaces <bond网卡名>
get_bond_subinterfaces() {
    local bond="$1"
    local result

    if [ -z "$bond" ]; then
        echo "No bond name provided"
        return 1
    fi

    result=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E "^${bond}\." | sort -u | cut -d'@' -f1)
    local ret=$?

    if [ $ret -ne 0 ]; then
        echo "Failed to list subinterfaces for bond $bond"
        return $ret
    fi

    echo "$result"
    return 0
}

# 获取bond网卡绑定的物理网卡
# 使用方法：get_bond_slaves <bond网卡名>
get_bond_slaves() {
    local bond="$1"
    local result

    if [ -z "$bond" ]; then
        echo "No bond name provided"
        return 1
    fi

    if [ ! -f "/proc/net/bonding/$bond" ]; then
        echo "/proc/net/bonding/$bond not exists"
        return 1
    fi

    result=$(grep "Slave Interface" "/proc/net/bonding/$bond" 2>/dev/null | awk '{print $3}' | sort -u)
    local ret=$?

    if [ $ret -ne 0 ]; then
        echo "Failed to list slave interfaces for bond $bond"
        return $ret
    fi

    echo "$result"
    return 0
}

# 获取指定物理网卡的最大支持速率
# 使用方法：get_max_supported_speed <物理网卡名>
get_max_supported_speed() {
    local nic=$1
    if [ -z "$nic" ]; then
        echo "Error: missing interface name" >&2
        return 1
    fi

    local max_speed
    max_speed=$(ethtool "$nic" 2>/dev/null | awk '
        /Supported link modes:/ {flag=1; next}
        /^[^[:space:]]/ {flag=0}    
        flag {
            if (match($0, /[0-9]+/, a)) print a[0]
        }
    ' | sort -nr | head -1)

    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "Failed to list slave interfaces for bond $bond"
        return $ret
    fi

    if [ -z "$max_speed" ]; then
        echo "NIC $nic Supported link MaxSpeed Unknown"
        return 1
    else
        echo "$max_speed"
        return 0
    fi
}

# 获取所有的 provider-networks.kubeovn.io
# 使用方法：get_provider_networks
get_provider_networks() {
    provider_networks=$(kubectl get provider-networks.kubeovn.io -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}')
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "Failed to list provider-networks.kubeovn.io"
        return $ret
    fi

    echo "$provider_networks"
    return 0
}

# 获取 provider-networks.kubeovn.io 中指定的网卡
# 使用方法：get_default_interface <provider-network名>
get_default_interface() {
    local provider_network=$1
    if [ -z "$provider_network" ]; then
        echo "Error: missing provider_network name" >&2
        return 1
    fi

    defaultInterface=$(kubectl get provider-networks.kubeovn.io "$provider_network" -o jsonpath='{.spec.defaultInterface}')
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "Failed to get defaultInterface for provider-networks.kubeovn.io $provider_network"
        return $ret
    fi

    echo "$defaultInterface"
    exit 0
}

# 获取 provider-networks.kubeovn.io 中绑定的 vlan id
# 使用方法：get_provider_network_vlans <provider-network名>
get_provider_network_vlans() {
    local provider_network=$1
    if [ -z "$provider_network" ]; then
        echo "Error: missing provider_network name" >&2
        return 1
    fi

    provider_network_vlans=$(kubectl get vlans.kubeovn.io -o jsonpath="{range .items[?(@.spec.provider==\"${provider_network}\")]}{.spec.id}{\"\n\"}{end}" | sort -n)
    local ret=$?
    if [ $ret -ne 0 ]; then
        echo "Failed to get vlan ids for provider-networks.kubeovn.io $provider_network"
        return $ret
    fi

    echo "$provider_network_vlans"
    return 0
}
