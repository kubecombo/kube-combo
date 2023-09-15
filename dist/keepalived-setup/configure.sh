#!/bin/bash
set -euo pipefail

TEMPLATE_CONF=temp-keepalived.conf.j2
CONF=/etc/keepalived/keepalived.conf
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

# prepare keepalived.conf
if [ ! -f CONF ]; then
    mv $CONF keepalived.conf.orig
    cp $TEMPLATE_CONF keepalived.conf.j2
fi


# use j2 to generate keepalived.conf
j2 $CONF $VALUES_YAML -o $CONF

# start keepalived
/usr/sbin/keepalived --log-console --log-detail --dont-fork --config-id="${POD_NAME}" --use-file=/etc/keepalived.d/keepalived.conf --pid=/etc/keepalived.pid/keepalived.pid
