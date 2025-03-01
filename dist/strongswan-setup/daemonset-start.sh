#!/bin/bash
set -eux
# k8s daemonset use this script to start ipsec static pod on node

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

# clean up old ipsecvpn certs and conf cache dir /etc/host-init-ipsecvpn to refresh
rm -fr "${CACHE_HOME}/*"

# copy all ipsecvpn server need file from /etc/ipsecvpn to /etc/host-init-ipsecvpn
# fix:// todo:// wait connection is ready and then copy it
\cp -r "${CONF_HOME}/*" "${CACHE_HOME}/"
\cp "${HOSTS_HOME}" "${CACHE_HOME}/"

echo "show /etc/host-init-ipsecvpn files .............."
ls -lR "${CACHE_HOME}/"

echo "deploy static pod /etc/kubernetes/manifests .............."
\cp "/static-strongswan.yaml" "/etc/kubernetes/manifests"

echo "k8s static pod should run /etc/host-init-ipsecvpn/static-pod-start.sh .............."
echo "k8s static pod will copy host, certs, config file from /etc/host-init-ipsecvpn to pod /etc/swanctl .............."
echo "alreay setup ssl vpn certs and config, sleep, you can use this pod to debug .............."
echo "this is also a debug pod .............."
echo "sleep .............."
sleep infinity
