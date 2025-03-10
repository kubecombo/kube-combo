#!/bin/bash
set -eux
# k8s static pod use this script to start ipsecvpn server on node
# 1. k8s static pod copy ipsec certs from /etc/host-init-strongswan to pod /etc/ipsecvpn
# 2. k8s static pod copy ipsec conf from /etc/host-init-strongswan to pod /etc/swanctl
# 3. k8s static pod copy etc hosts from host-init to pod /etc/hosts
# 4. start ipsecvpn server

CACHE_HOME=${CACHE_HOME:-/etc/host-init-strongswan}
if [ ! -e "/etc/hosts.ori" ]; then
    # backup hosts
    cp /etc/hosts /etc/hosts.ori
fi
# 3. copy hosts
if [ -d "${CACHE_HOME}" ]; then
    \cp "${CACHE_HOME}/hosts.ipsec" "/etc/"
    cat /etc/hosts.ori >/etc/hosts
    cat /etc/hosts.ipsec >>/etc/hosts
fi
