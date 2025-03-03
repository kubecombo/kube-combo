#!/bin/bash
set -eux
# k8s static pod use this script to start ipsecvpn server on node
# 1. k8s static pod copy file from host-init to pod /etc/ipsecvpn
# 2. start ipsecvpn server

# make it runable in any directory
CACHE_HOME=${CACHE_HOME:-/etc/host-init-strongswan}
CONF_HOME=${CONF_HOME:-/etc/swanctl}
HOSTS_HOME=${HOSTS_HOME:-/etc/hosts}
# use READY_FLAG to check /etc/hosts is aleady has connections
READY_FLAG="STRONGSWAN_CONTENT_END"

# wait connection is ready and then copy it
# loop to check if hosts has connection
echo "check if has ${CACHE_HOME}/swanctl.conf ............"
while [ ! -f "${CACHE_HOME}/swanctl.conf" ]; do
    echo "waiting for ${CACHE_HOME}/swanctl.conf ............"
    sleep 5
done
echo "found ${CACHE_HOME}/swanctl.conf ............"
cat "${CACHE_HOME}/swanctl.conf"

echo "check if ${CACHE_HOME}/hosts ready ............"
while true; do
    if grep -q "${READY_FLAG}" "${CACHE_HOME}/hosts"; then
        echo "found connections: ${READY_FLAG}"
        break
    else
        echo "not found connections: ${READY_FLAG}, waiting"
        sleep 5
    fi
done

# clean up old ipsecvpn certs and conf cache to use new in /etc/host-init-strongswan
rm -fr "/etc/swanctl/*"

\cp -r "${CACHE_HOME}/private" "${CONF_HOME}/"
\cp -r "${CACHE_HOME}/x509" "${CONF_HOME}/"
\cp -r "${CACHE_HOME}/x509ca" "${CONF_HOME}/"

\cp "${CACHE_HOME}/swanctl.conf" "${CONF_HOME}/"

\cp "${CACHE_HOME}/hosts" "${CONF_HOME}/"

# start ipsecvpn server
echo "Running ipsecvpn .............."
/usr/sbin/charon-systemd
