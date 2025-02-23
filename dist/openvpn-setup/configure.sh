#!/bin/bash
#set -eux

cidr2mask() {
   # Number of args to shift, 255..255, first non-255 byte, zeroes
   set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
   [ $1 -gt 1 ] && shift "$1" || shift
   echo ${1-0}.${2-0}.${3-0}.${4-0}
}

cidr2net() {
    ip="${1%/*}"
    mask="${1#*/}"
    octets=$(echo "$ip" | tr '.' '\n')
    netOctets=""
    i=0
    for octet in $octets; do
        i=$((i+1))
        if [ $i -le $(( mask / 8)) ]; then
            netOctets="$netOctets.$octet"
        elif [ $i -eq  $(( mask / 8 +1 )) ]; then
            netOctets="$netOctets.$((((octet / ((256 / ((2**((mask % 8)))))))) * ((256 / ((2**((mask % 8))))))))"
        else
            netOctets="$netOctets.0"
        fi
    done

    echo "${netOctets#.}"
}

# make it runable in any directory
CONF_HOME=${CONF_HOME:-/etc/openvpn}
CONF="$CONF_HOME/openvpn.conf"
SETUP_HOME="$CONF_HOME/setup"
echo "setup openvpn in ${SETUP_HOME} .............."

# use cert-manager secrets and user defined dh secret
bash -x "${SETUP_HOME}/copy-certs.sh"
# or generate certs with easyrsa
#bash -x "${SETUP_HOME}/setup-certs.sh"

intAndIP="$(ip route get 8.8.8.8 | awk '/8.8.8.8/ {print $5 "-" $7}')"
int="${intAndIP%-*}"
ip="${intAndIP#*-}"
cidr="$(ip addr show dev "$int" | awk -vip="$ip" '($2 ~ ip) {print $2}')"
SSL_VPN_NETWORK="$(echo "${SSL_VPN_SUBNET_CIDR}" | tr "/" " " | awk '{ print $1 }')"
ssk_vpn_subnet_mask="$(echo "${SSL_VPN_SUBNET_CIDR}" | tr "/" " " | awk '{ print $2 }')"
SSL_VPN_SUBNET_MASK=$(cidr2mask "${ssk_vpn_subnet_mask}")
NETWORK=$(cidr2net "${cidr}")
NETMASK=$(cidr2mask "${cidr#*/}")
echo "DEBUG .............."
echo "SSL_VPN_NETWORK ${SSL_VPN_NETWORK} SSL_VPN_SUBNET_MASK ${SSL_VPN_SUBNET_MASK}"
echo "SSL_VPN_PROTO ${SSL_VPN_PROTO} SSL_VPN_PORT ${SSL_VPN_PORT}"
echo "SSL_VPN_CIPHER ${SSL_VPN_CIPHER}"
echo "NETWORK ${NETWORK} NETMASK ${NETMASK}"

iptables -t nat -A POSTROUTING -s "${SSL_VPN_NETWORK}/${SSL_VPN_SUBNET_MASK}" -o eth0 -j MASQUERADE

mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

SEARCH=$(grep -v '^#' /etc/resolv.conf | grep search | awk '{$1=""; print $0}')
FORMATTED_SEARCH=""
for DOMAIN in $SEARCH; do
  FORMATTED_SEARCH="${FORMATTED_SEARCH}push \"dhcp-option DOMAIN-SEARCH ${DOMAIN}\"\n"
done
# create openvpn.conf
\cp -f "${SETUP_HOME}/openvpn.conf" "${CONF}"

# format openvpn.conf
sed 's|SSL_VPN_PROTO|'"${SSL_VPN_PROTO}"'|' -i "${CONF}"
sed 's|SSL_VPN_PORT|'"${SSL_VPN_PORT}"'|' -i "${CONF}"

sed 's|SSL_VPN_NETWORK|'"${SSL_VPN_NETWORK}"'|' -i "${CONF}"
sed 's|SSL_VPN_SUBNET_MASK|'"${SSL_VPN_SUBNET_MASK}"'|' -i "${CONF}"
sed 's|CIPHER|'"${SSL_VPN_CIPHER}"'|' -i "${CONF}"
sed 's|AUTH|'"${SSL_VPN_AUTH}"'|' -i "${CONF}"


# NETWORK is in SSL_VPN_NETWORK, so leave it last to sed
sed 's|NETWORK|'"${NETWORK}"'|' -i "${CONF}"
sed 's|NETMASK|'"${NETMASK}"'|' -i "${CONF}"

# DNS
sed 's|SSL_VPN_K8S_SEARCH|'"${FORMATTED_SEARCH}"'|' -i "${CONF}"

# debug openvpn.conf
echo "cat ${CONF} start .............."
cat "${CONF}"
echo "cat ${CONF} end .............."

# show openvpn version
echo "openvpn --version"
openvpn --version

# if host-init directory is exist, skip running openvpn here
# it will be run in k8s static pod later
if [ -d "${CONF_HOME}/host-init" ]; then
    echo "host-init directory is exist, skip running openvpn .............."
    sleep infinity
fi
echo "Running openvpn with config .............."
echo "openvpn --config ${CONF}"
openvpn --config "${CONF}"
