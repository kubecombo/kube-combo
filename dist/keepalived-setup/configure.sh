#!/bin/bash
set -euo pipefail
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
printf "KA_VIP: %s\n" "${KEEPALIVED_VIP}" > $VALUES_YAML
printf "KA_VRID: %s\n" "${KEEPALIVED_VIRTUAL_ROUTER_ID}" >> $VALUES_YAML

echo "prepare keepalived.conf..."
cp $TEMPLATE_CONF keepalived.conf.j2

# use j2 to generate keepalived.conf
j2 keepalived.conf.j2 $VALUES_YAML -o $CONF

echo "start keepalived..."
host=$(hostname)
/usr/sbin/keepalived --log-console --log-detail --dont-fork --config-id="${host}" --use-file="${CONF}"
