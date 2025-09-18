#!/bin/bash
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

generate_yaml_detection() {
    if [ "$#" -ne 1 ]; then
        log_err "Usage: generate_yaml_detection <section_name>" >&2
        return 1
    fi

    local section_name="$1"
    cat <<EOF
$section_name:
EOF
}

generate_yaml_entry() {
    if [ "$#" -ne 4 ]; then
        log_err "Usage: generate_yaml_entry <key> <value> <err> <level>" >&2
        return 1
    fi

    local key="$1"
    local value="$2"
    local err="$3"
    local level="$4"

    cat <<EOF
  - key: "$key"
    value: "$value"
    err: "$err"
    level: "$level"
EOF
}

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

get_bond_subinterfaces() {
    local bond="$1"
    local result

    if [ -z "$bond" ]; then
        echo "No bond name provided"
        return 1
    fi

    result=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E "^${bond}\." | sort -u)
    local ret=$?

    if [ $ret -ne 0 ]; then
        echo "Failed to list subinterfaces for bond $bond"
        return $ret
    fi

    echo "$result"
    return 0
}

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
