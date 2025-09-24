#!/bin/bash

# 通过Post将结果返回只后端
# 使用方法：send_post() $EIS_POST_URL $RESULT admin
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

	if ! [[ "$status" =~ ^2 ]]; then
		echo "POST request failed with status $status, response: $response"
		return 100
	fi

	echo "$response"
	return 0
}
