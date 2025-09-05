#!/bin/bash

generate_yaml_detection() {
	if [ "$#" -ne 1 ]; then
		echo "用法: generate_yaml_detection <section_name>" >&2
		return 1
	fi

	local section_name="$1"
	cat << EOF
$section_name:
EOF
}

generate_yaml_entry() {
	if [ "$#" -ne 3 ]; then
		echo "用法: generate_yaml_entry <key> <value> <err>" >&2
		return 1
	fi

	local key="$1"
	local value="$2"
	local err="$3"

	cat << EOF
  - key: $key
    value: "$value"
    err: "$err"
EOF
}
