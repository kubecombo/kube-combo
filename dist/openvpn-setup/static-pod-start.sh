#!/bin/bash
#set -eux
# k8s static pod use this script to start openvpn server on node

# k8s static pod copy file from host-init to pod /etc/openvpn
# and start openvpn server


# clean /etc/openvpn/ dir
rm -fr /etc/openvpn/*

# copy all openvpn server need file to /etc/openvpn
\cp /etc/openvpn/host-init/openvpn.conf /etc/openvpn/
\cp -r /etc/openvpn/host-init/certs /etc/openvpn/
mkdir -p /etc/openvpn/dh
\cp /etc/openvpn/host-init/dh.pem /etc/openvpn/dh

# start openvpn server
echo "Running openvpn with config .............."
echo "openvpn --config ${CONF}"
openvpn --config /etc/openvpn/openvpn.conf
