#!/bin/bash
set -eux
echo "setup keepalived..."

TEMPLATE_CONF=temp-keepalived.conf.j2
CONF=/etc/keepalived.d/keepalived.conf
VALUES_YAML=values.yaml

# load values
if [ -z "$KEEPALIVED_VIP" ]; then
    echo "KEEPALIVED_VIP is empty."
    exit 1
fi
if [ -z "$KEEPALIVED_VIRTUAL_ROUTER_ID" ]; then
    echo "KEEPALIVED_VIRTUAL_ROUTER_ID is empty."
    exit 1
fi
if [ -z "$KEEPALIVED_NIC" ]; then
    echo "KEEPALIVED_NIC is empty."
    exit 1
fi

# prepare values.yaml
printf "instances: \n" >"${VALUES_YAML}"

# This priority value must be within the range of 0 to 255
# random generate a priority value
priority=$(shuf -i 0-255 -n 1)

# example KEEPALIVED_NIC="eth0,eth1"
# example KEEPALIVED_VIP="192.168.0.100,192.168.1.100"
nic1, nic2 = $(echo "${KEEPALIVED_NIC}" | tr "," "\n")
vip1, vip2 = $(echo "${KEEPALIVED_VIP}" | tr "," "\n")
router_id1 = $(echo "${KEEPALIVED_VIRTUAL_ROUTER_ID}" | tr "," "\n")
router_id2 = router_id1 + 1

if [ ! -z "$vip1" ]; then
    echo "prepare vip ${vip1} nic ${nic1} ..."
    printf "  - name: %s\n" "${nic1}" >>"${VALUES_YAML}"
    printf "    vip: %s\n" "${vip1}" >>"${VALUES_YAML}"
    printf "    nic: %s\n" "${nic1}" >>"${VALUES_YAML}"
    printf "    router_id: %s\n" "${router_id1}" >>"${VALUES_YAML}"
    printf "    priority: %s\n" "${priority}" >>"${VALUES_YAML}"
fi

if [ ! -z "$vip2" ]; then
    echo "prepare vip ${vip2} nic ${nic2} ..."
    printf "  - name: %s\n" "${nic2}" >>"${VALUES_YAML}"
    printf "    vip: %s\n" "${vip2}" >>"${VALUES_YAML}"
    printf "    nic: %s\n" "${nic2}" >>"${VALUES_YAML}"
    printf "    router_id: %s\n" "${router_id2}" >>"${VALUES_YAML}"
    printf "    priority: %s\n" "${priority}" >>"${VALUES_YAML}"
fi

echo "cat ${VALUES_YAML}..."
cat "${VALUES_YAML}"

echo "prepare keepalived.conf..."
cp "${TEMPLATE_CONF}" keepalived.conf.j2

# use j2 to generate keepalived.conf
j2 keepalived.conf.j2 "${VALUES_YAML}" -o "${CONF}"

echo "keepalived.conf:"
cat "${CONF}"

echo "start keepalived..."
host=$(hostname)
/usr/sbin/keepalived --log-console --log-detail --dont-fork --config-id="${host}" --use-file="${CONF}"
