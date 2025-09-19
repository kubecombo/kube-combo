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

    result=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -E "^${bond}\." | sort -u | cut -d'@' -f1)
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

send_post() {
    local url="$1"
    local json_str="$2"
    local user_id="$3"

    local headers=(-H "Content-Type: application/json")
    if [[ -n "$user_id" ]]; then
        headers+=(-H "user_id: $user_id")
    fi

    local response status
    response=$(curl -s -w "%{http_code}" -X POST "$url" "${headers[@]}" -d "$json_str")
    status="${response: -3}"
    response="${response:0:-3}"

    if [[ "$status" != 2* ]]; then
        echo "POST request failed with status $status"
        return 1
    fi

    echo "$response"
    return 0
}
