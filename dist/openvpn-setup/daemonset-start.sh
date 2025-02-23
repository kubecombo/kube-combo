#!/bin/bash
#set -eux
# k8s daemonset use this script to start static pod on node

# make it runable in any directory
CONF_HOME=${CONF_HOME:-/etc/openvpn}
SETUP_HOME="$CONF_HOME/setup"
echo "debug setup openvpn in ${SETUP_HOME} .............."
bash -x "${SETUP_HOME}/configure.sh"

# clean up openvpn certs and conf cache dir /etc/host-init-openvpn
rm -fr "/etc/host-init-openvpn/*"

# copy all openvpn server need file from /etc/openvpn to /etc/host-init-openvpn
\cp "$SETUP_HOME/static-pod-start.sh" "/etc/host-init-openvpn"
\cp "$CONF_HOME/openvpn.conf" "/etc/host-init-openvpn"
\cp -r "$CONF_HOME/certs" "/etc/host-init-openvpn"
\cp -L "$CONF_HOME/dh/dh.pem" "/etc/host-init-openvpn"

echo "show /etc/host-init-openvpn files .............."
ls -lR "/etc/host-init-openvpn"

echo "k8s static pod should run /etc/host-init-openvpn/static-pod-start.sh .............."
echo "k8s static pod will copy certs and config file from /etc/host-init-openvpn to pod /etc/openvpn .............."
echo "k8s static pod will run openvpn --config /etc/openvpn/openvpn.conf .............."
echo "alreay setup ssl vpn certs and config, sleep, you can use this pod to debug .............."
echo "this is also a debug pod .............."
echo "sleep .............."
sleep infinity
