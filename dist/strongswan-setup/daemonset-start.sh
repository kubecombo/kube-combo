#!/bin/bash
set -eux

echo "k8s static pod should run /etc/host-init-ipsecvpn/static-pod-start.sh .............."
echo "k8s static pod will copy host, certs, config file from /etc/host-init-ipsecvpn to pod /etc/swanctl .............."
echo "this is also a debug pod .............."
echo "sleep .............."
sleep infinity
