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

	# 提取 Supported link modes 中的数值并取最大
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
