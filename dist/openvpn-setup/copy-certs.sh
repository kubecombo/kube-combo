#!/bin/bash
set -eux
EASY_RSA_LOC="/etc/openvpn/certs"

# pod mount secret to /etc/ovpn/certs, but not that fast
# after pod start, the secret maybe is not mounted yet

while [ ! -f /etc/ovpn/certs/tls.key ]
do
    sleep 2
    echo "waiting for /etc/ovpn/certs/tls.key ............"
done

while [ ! -f /etc/ovpn/dh/dh.pem ]
do
    sleep 2
    echo "waiting for /etc/ovpn/dh/dh.pem ............"
done

cp /etc/ovpn/certs/tls.key $EASY_RSA_LOC/pki/private/server.key
# chmod 600 key to eliminate the warning.
chmod 600 $EASY_RSA_LOC/pki/private/server.key

cp /etc/ovpn/certs/ca.crt $EASY_RSA_LOC/pki/ca.crt

openssl x509 --nout --text --in /etc/ovpn/certs/tls.crt > $EASY_RSA_LOC/pki/issued/server.crt 
# cat /etc/ovpn/certs/tls.crt >> $EASY_RSA_LOC/pki/issued/server.crt

cp /etc/ovpn/dh/dh.pem $EASY_RSA_LOC/pki/dh.pem

