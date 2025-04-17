#!/bin/bash
set -eux
POD_IP=${POD_IP:-}

if [ -z "$POD_IP" ]; then
    echo "POD_IP is not set, please set it to the pod IP in pod env"
    exit 1
fi

/usr/bin/nc -vzu $POD_IP 1194
if [ $? -eq 0 ]; then
    echo "openvpn server is running"
else
    echo "openvpn server is not running"
    exit 1
fi