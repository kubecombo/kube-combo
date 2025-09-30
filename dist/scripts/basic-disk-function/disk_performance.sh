#!/bin/bash
set -e
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/log.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../util/util.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../util/curl.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}" || exit

log_info "Start disk performance detection (fio)"
YAML=$(generate_yaml_detection "disk_performance_results")$'\n'

tmp_yaml=$(mktemp)
test_dir="/tmp/disk-test"
mkdir -p "$test_dir" || {
  echo "  - key: \"fio测试\"" >> "$tmp_yaml"
  echo "    value: \"失败\"" >> "$tmp_yaml"
  echo "    err: \"测试目录创建失败\"" >> "$tmp_yaml"
  echo "    level: \"error\"" >> "$tmp_yaml"
  YAML+=$(cat "$tmp_yaml")
  rm -f "$tmp_yaml"
  log_debug "$YAML"
  RESULT=$( echo "$YAML" | jinja2 check_disk.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
  log_result  "$RESULT"
  exit 1
}

fio_cmd="nsenter -t 1 -m -u -i -n fio --name=disk_perf_test --rw=randrw --direct=1 --bs=4k --numjobs=4 --iodepth=32 --size=100M --runtime=10 --group_reporting --directory=$test_dir"
fio_output=$(eval $fio_cmd 2>&1)
fio_exit_code=$?
rm -rf "$test_dir"

if [ $fio_exit_code -ne 0 ]; then
  echo "  - key: \"FIO Test\"" >> "$tmp_yaml"
  echo "    value: \"Failed\"" >> "$tmp_yaml"
  echo "    err: \"fio execution failed\"" >> "$tmp_yaml"
  echo "    level: \"error\"" >> "$tmp_yaml"
else
  read_iops=$(echo "$fio_output" | grep -i "read:.*iops" | awk -F'[=,]' '{print $2}' | sed 's/ //g')
  write_iops=$(echo "$fio_output" | grep -i "write:.*iops" | awk -F'[=,]' '{print $2}' | sed 's/ //g')
  read_bw=$(echo "$fio_output" | grep -i "read:.*bw" | awk -F'BW=' '{print $2}' | awk '{print $1}')
  write_bw=$(echo "$fio_output" | grep -i "write:.*bw" | awk -F'BW=' '{print $2}' | awk '{print $1}')
  echo "  - key: \"Read IOPS\"" >> "$tmp_yaml"
  echo "    value: \"${read_iops:-Unknown}\"" >> "$tmp_yaml"
  echo "    err: \"\"" >> "$tmp_yaml"
  echo "    level: \"\"" >> "$tmp_yaml"
  echo "  - key: \"Written IOPS\"" >> "$tmp_yaml"
  echo "    value: \"${write_iops:-Unknown}\"" >> "$tmp_yaml"
  echo "    err: \"\"" >> "$tmp_yaml"
  echo "    level: \"\"" >> "$tmp_yaml"
  echo "  - key: \"Read Bandwidth\"" >> "$tmp_yaml"
  echo "    value: \"${read_bw:-Unknown}\"" >> "$tmp_yaml"
  echo "    err: \"\"" >> "$tmp_yaml"
  echo "    level: \"\"" >> "$tmp_yaml"
  echo "  - key: \"Written Bandwidth\"" >> "$tmp_yaml"
  echo "    value: \"${write_bw:-Unknown}\"" >> "$tmp_yaml"
  echo "    err: \"\"" >> "$tmp_yaml"
  echo "    level: \"\"" >> "$tmp_yaml"
fi

YAML+=$(cat "$tmp_yaml")
rm -f "$tmp_yaml"

log_debug "$YAML"
RESULT=$( echo "$YAML" | jinja2 check_disk.j2 -D NodeName="$NodeName" -D Timestamp="$Timestamp")
log_result  "$RESULT"
set +e
log_debug "Start posting detection result"
response=$(send_post "$EIS_POST_URL" "$RESULT" admin)
ret=$?
log_debug "$(echo "$response" | tr '\n' ' ')"
set -e
exit $ret