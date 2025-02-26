#!/bin/bash
set -eux

# make it runable in any directory
CONF_HOME=${CONF_HOME:-/etc/openvpn}
CERT_MANAGER_HOME=${CERT_MANAGER_HOME:-/etc/openvpn/certmanager}
EASY_RSA_CERTS_HOME=${EASY_RSA_CERTS_HOME:-/etc/openvpn/certs}

# make sure the directories are there
echo "openvpn home in ${CONF_HOME} .............."
tree "${CONF_HOME}"
echo "make sure ${CERT_MANAGER_HOME} has ca.crt, tls.crt, tls.key"
tree "${CERT_MANAGER_HOME}"
echo "make sure ${EASY_RSA_CERTS_HOME} is empty .............."
tree "${EASY_RSA_CERTS_HOME}"

# copy certs from cert-manager to easy-rsa
cp "${CERT_MANAGER_HOME}/ca.crt" "$EASY_RSA_CERTS_HOME"
cp "${CERT_MANAGER_HOME}/tls.crt" "$EASY_RSA_CERTS_HOME"
cp "${CERT_MANAGER_HOME}/tls.key" "$EASY_RSA_CERTS_HOME"

echo "make sure ${EASY_RSA_CERTS_HOME} has ca.crt, tls.crt, tls.key"
tree "${EASY_RSA_CERTS_HOME}"

# pod mount secret to /etc/openvpn/certs, but not that fast
# after pod start, the secret maybe is not mounted yet

while [ ! -f "${EASY_RSA_CERTS_HOME}/ca.crt" ]; do
    sleep 1
    echo "waiting for ${EASY_RSA_CERTS_HOME}/ca.crt ............"
done

while [ ! -f "${EASY_RSA_CERTS_HOME}/tls.crt" ]; do
    sleep 1
    echo "waiting for ${EASY_RSA_CERTS_HOME}/tls.crt ............"
done

while [ ! -f "${EASY_RSA_CERTS_HOME}/tls.key" ]; do
    sleep 1
    echo "waiting for ${EASY_RSA_CERTS_HOME}/tls.key ............"
done

# dh pem is managed by k8s secret mount, so it may not be there yet
while [ ! -f /etc/openvpn/dh/dh.pem ]; do
    sleep 1
    echo "waiting for /etc/openvpn/dh/dh.pem ............"
done

cp "${EASY_RSA_CERTS_HOME}/tls.key" "$EASY_RSA_CERTS_HOME/pki/private/server.key"
# chmod 600 key to eliminate the warning.
chmod 600 "$EASY_RSA_CERTS_HOME/pki/private/server.key"

cp "${EASY_RSA_CERTS_HOME}/ca.crt" "$EASY_RSA_CERTS_HOME/pki/ca.crt"

openssl x509 --nout --text --in "${EASY_RSA_CERTS_HOME}/tls.crt" >"$EASY_RSA_CERTS_HOME/pki/issued/server.crt"
# cat /etc/openvpn/certs/tls.crt >> $EASY_RSA_LOC/pki/issued/server.crt

cp /etc/openvpn/dh/dh.pem "$EASY_RSA_CERTS_HOME/pki/dh.pem"
