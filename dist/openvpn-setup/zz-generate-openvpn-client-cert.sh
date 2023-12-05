#!/bin/bash
set -euo pipefail
# generate client cert based given client key name and service ip
# $1 should be client key name
# PUBLIC_IP should be lb service external ip or floating ip

CLIENT_KEY_NAME=$1
PUBLIC_IP=$2

EASY_RSA_LOC="/etc/openvpn/certs"
cd $EASY_RSA_LOC

# generate client cert
/usr/share/easy-rsa/easyrsa build-client-full "${CLIENT_KEY_NAME}" nopass
cat >${EASY_RSA_LOC}/pki/"${CLIENT_KEY_NAME}".openvpn <<EOF
client
nobind
dev tun
remote-cert-tls server # mitigate mitm
# 注意这里由于 cert-manager 签的 secret 没有 Key Usage, 所以这里需要屏蔽掉
# https://superuser.com/questions/1446201/openvpn-certificate-does-not-have-key-usage-extension
remote ${PUBLIC_IP} ${SSL_VPN_PORT} udp  
# default udp 1194
# defualt tcp 443
redirect-gateway def1
<key>
$(cat ${EASY_RSA_LOC}/pki/private/"${CLIENT_KEY_NAME}".key)
</key>
<cert>
$(cat ${EASY_RSA_LOC}/pki/issued/"${CLIENT_KEY_NAME}".crt)
</cert>
<ca>
$(cat ${EASY_RSA_LOC}/pki/ca.crt)
</ca>
EOF
cat pki/"${CLIENT_KEY_NAME}".openvpn
