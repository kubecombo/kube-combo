#!/bin/bash
set -eux

echo "make sure /etc/openvpn/certmanager has ca.crt, tls.crt, tls.key"
tree /etc/openvpn/

CERT_MANAGER_CERTS="/etc/openvpn/certmanager"
EASY_RSA_LOC="/etc/openvpn/certs"

cp "${CERT_MANAGER_CERTS}/ca.crt" $EASY_RSA_LOC
cp "${CERT_MANAGER_CERTS}/tls.crt" $EASY_RSA_LOC
cp "${CERT_MANAGER_CERTS}/tls.key" $EASY_RSA_LOC

echo "make sure /etc/openvpn/certs has ca.crt, tls.crt, tls.key"
tree $EASY_RSA_LOC

# pod mount secret to /etc/openvpn/certs, but not that fast
# after pod start, the secret maybe is not mounted yet

while [ ! -f /etc/openvpn/certs/tls.key ]
do
    sleep 2
    echo "waiting for /etc/openvpn/certs/tls.key ............"
done

while [ ! -f /etc/openvpn/certs/ca.crt ]
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

