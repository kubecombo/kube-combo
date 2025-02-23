#!/bin/bash
#set -eux
# k8s daemonset use this script to start static pod on node

# make it runable in any directory
CONF_HOME=${CONF_HOME:-/etc/openvpn}
SETUP_HOME="$CONF_HOME/setup"
echo "debug setup openvpn in ${SETUP_HOME} .............."
bash -x "${SETUP_HOME}/configure.sh"

# clean up tmp dir host-init
rm -fr "$CONF_HOME/host-init/*"

# copy all openvpn server need file to host-init
\cp "$SETUP_HOME/static-pod-start.sh" "$CONF_HOME/host-init/"
\cp "$CONF_HOME/openvpn.conf" "$CONF_HOME/host-init/"
\cp -r "$CONF_HOME/certs" "$CONF_HOME/host-init/"
\cp -L "$CONF_HOME/dh/dh.pem" "$CONF_HOME/host-init/"

echo "show $CONF_HOME/host-init/ files .............."
ls -lR "$CONF_HOME/host-init/"

echo "k8s static pod should run $CONF_HOME/host-init/static-pod-start.sh .............."
echo "k8s static pod will copy certs and config file from host-init to pod /etc/openvpn .............."
echo "k8s static pod will run openvpn --config /etc/openvpn/openvpn.conf .............."
echo "alreay setup ssl vpn certs and config, sleep, you can use this pod to debug .............."
echo "this is also a debug pod .............."
echo "sleep .............."
sleep infinity

# k8s static pod will copy file from this host-init to pod /etc/openvpn