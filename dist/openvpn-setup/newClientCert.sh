#!/bin/bash
set -euo pipefail
# generate client cert based given client key name and service ip
# $1 should be client key name
# PUBLIC_IP should be lb service external ip or floating ip
client_key_name=$1

EASY_RSA_LOC="/etc/openvpn/certs"
cd $EASY_RSA_LOC
/usr/share/easy-rsa/easyrsa build-client-full "${client_key_name}" nopass
cat >${EASY_RSA_LOC}/pki/"${client_key_name}".ovpn <<EOF
client
nobind
dev tun
remote-cert-tls server # mitigate mitm
# 注意这里由于 cert-manager 签的secret 没有 Key Usage, 所以这里需要屏蔽掉
# https://superuser.com/questions/1446201/openvpn-certificate-does-not-have-key-usage-extension
remote ${PUBLIC_IP} 1194 udp  
# default udp 1194
# defualt tcp 443
redirect-gateway def1
<key>
$(cat ${EASY_RSA_LOC}/pki/private/"${client_key_name}".key)
</key>
<cert>
$(cat ${EASY_RSA_LOC}/pki/issued/"${client_key_name}".crt)
</cert>
<ca>
$(cat ${EASY_RSA_LOC}/pki/ca.crt)
</ca>
EOF
cat pki/"${client_key_name}".ovpn
