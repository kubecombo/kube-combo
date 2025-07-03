#!/bin/bash

env | grep -i -E "ping|dns|host|enable"

./pinger --ds-namespace="$POD_NAMESPACE" \
         --ds-name="$DS_NAME" \
         --mode="server" \
         --ping="$PING" \
         --tcpping="$TCP_PING" \
         --udpping="$UDP_PING" \
         --dnslookup="$DNS" \
         --enable-metrics="$ENABLE_METRICS" \
         --enable-node-ip-check="$HOST_NETWORK"
