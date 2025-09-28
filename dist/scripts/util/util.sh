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
