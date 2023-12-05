#!/bin/bash
set -eux
EASY_RSA_LOC="/etc/openvpn/certs"

# pod mount secret to /etc/OpenVpn/certs, but not that fast
# after pod start, the secret maybe is not mounted yet

while [ ! -f /etc/OpenVpn/certs/tls.key ]
do
    sleep 2
    echo "waiting for /etc/OpenVpn/certs/tls.key ............"
done

while [ ! -f /etc/OpenVpn/dh/dh.pem ]
do
    sleep 2
    echo "waiting for /etc/OpenVpn/dh/dh.pem ............"
done

cp /etc/OpenVpn/certs/tls.key $EASY_RSA_LOC/pki/private/server.key
# chmod 600 key to eliminate the warning.
chmod 600 $EASY_RSA_LOC/pki/private/server.key

cp /etc/OpenVpn/certs/ca.crt $EASY_RSA_LOC/pki/ca.crt

openssl x509 --nout --text --in /etc/OpenVpn/certs/tls.crt > $EASY_RSA_LOC/pki/issued/server.crt 
# cat /etc/OpenVpn/certs/tls.crt >> $EASY_RSA_LOC/pki/issued/server.crt

cp /etc/OpenVpn/dh/dh.pem $EASY_RSA_LOC/pki/dh.pem

