#!/bin/bash
set -eux
# k8s static pod use this script to start ipsecvpn server on node
# 1. k8s static pod copy file from host-init to pod /etc/ipsecvpn
# 2. start ipsecvpn server

# make it runable in any directory
CACHE_HOME=${CACHE_HOME:-/etc/host-init-ipsecvpn}
CONF_HOME=${CONF_HOME:-/etc/swanctl}
HOSTS_HOME=${HOSTS_HOME:-/etc/hosts}
# use READY_FLAG to check /etc/hosts is aleady has connections
READY_FLAG="STRONGSWAN_CONTENT_END"

# wait connection is ready and then copy it
# loop to check if hosts has connection
while true; do
    if grep -q "$READY_FLAG" /etc/hosts; then  
        echo "found connections: $READY_FLAG"
        break
    else
        echo "not found connections: $READY_FLAG, waiting"
        sleep 5
    fi  
done  
while [ ! -f "${CONF_HOME}/swanctl.conf" ]; do
	echo "waiting for ${CONF_HOME}/swanctl.conf ............"
	sleep 5
done

# clean up old ipsecvpn certs and conf cache to use new in /etc/host-init-ipsecvpn
rm -fr "${CONF_HOME}/*"

\cp -r "${CACHE_HOME}/*" "${CONF_HOME}/"
\cp "${CACHE_HOME}/hosts" "${HOSTS_HOME}" 

echo "show ${CONF_HOME} files .............."
ls -lR "${CACHE_HOME}/"

# start ipsecvpn server
echo "Running ipsecvpn .............."
/usr/sbin/charon-systemd