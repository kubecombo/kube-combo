#!/bin/bash

env | grep -i -E "ping|dns"

./pinger --ds-namespace="$POD_NAMESPACE" --ds-name="$DS_NAME" --interval="$INTERVAL" --mode="server" --ping="$PING" --tcpping="$TCP_PING" --udpping="$UDP_PING" --dnslookup="$DNS"
