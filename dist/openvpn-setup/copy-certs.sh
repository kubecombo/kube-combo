#!/bin/bash
set -eux
EASY_RSA_LOC="/etc/openvpn/certs"

# pod mount secret to /etc/openvpn/certs, but not that fast
# after pod start, the secret maybe is not mounted yet

while [ ! -f /etc/openvpn/certs/tls.key ]
do
    sleep 2
    echo "waiting for /etc/openvpn/certs/tls.key ............"
done

while [ ! -f /etc/openvpn/dh/dh.pem ]
do
    sleep 2
    echo "waiting for /etc/openvpn/dh/dh.pem ............"
done

cp /etc/openvpn/certs/tls.key $EASY_RSA_LOC/pki/private/server.key
# chmod 600 key to eliminate the warning.
chmod 600 $EASY_RSA_LOC/pki/private/server.key

cp /etc/openvpn/certs/ca.crt $EASY_RSA_LOC/pki/ca.crt

openssl x509 --nout --text --in /etc/openvpn/certs/tls.crt > $EASY_RSA_LOC/pki/issued/server.crt 
# cat /etc/openvpn/certs/tls.crt >> $EASY_RSA_LOC/pki/issued/server.crt

cp /etc/openvpn/dh/dh.pem $EASY_RSA_LOC/pki/dh.pem

