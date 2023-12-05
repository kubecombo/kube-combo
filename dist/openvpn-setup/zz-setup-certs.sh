#!/bin/bash
set -euo pipefail
export EASYRSA_BATCH=1 # for non-interactive environments
EASY_RSA_LOC="/etc/openvpn/certs"
SERVER_CERT="${EASY_RSA_LOC}/pki/issued/server.crt"
if [ -e "$SERVER_CERT" ]
then
  echo "found existing certs - reusing"
else
  cp -R /usr/share/easy-rsa/* $EASY_RSA_LOC
  cd $EASY_RSA_LOC
  ./easyrsa init-pki
  echo "ca\n" | ./easyrsa build-ca nopass
  ./easyrsa build-server-full server nopass
  ./easyrsa gen-dh
fi

