#!/bin/bash
set -eux
# k8s static pod use this script to start openvpn server on node

# k8s static pod copy file from host-init to pod /etc/openvpn
# and start openvpn server


# clean /etc/openvpn/ dir
rm -fr /etc/openvpn/*

while [ ! -f "/etc/host-init-openvpn/openvpn.conf" ]
do
    sleep 1
    echo "waiting for /etc/host-init-openvpn/openvpn.conf ............"
done

while [ ! -d "/etc/host-init-openvpn/certs" ]
do
    sleep 1
    echo "waiting for /etc/host-init-openvpn/certs ............"
done

while [ ! -f "/etc/host-init-openvpn/dh.pem" ]
do
    sleep 1
    echo "waiting for /etc/host-init-openvpn/dh.pem ............"
done

# copy all openvpn server need file from /etc/host-init-openvpn to /etc/openvpn
\cp /etc/host-init-openvpn/openvpn.conf /etc/openvpn/
\cp -r /etc/host-init-openvpn/certs /etc/openvpn/
mkdir -p /etc/openvpn/dh
\cp /etc/host-init-openvpn/dh.pem /etc/openvpn/dh

# start openvpn server
echo "Running openvpn with config .............."
openvpn --config /etc/openvpn/openvpn.conf
