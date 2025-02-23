#!/bin/bash
#set -eux
# run configure.sh manually to debug

# make it runable in any directory
CONF_HOME=${CONF_HOME:-/etc/openvpn}
SETUP_HOME="$CONF_HOME/setup"
echo "debug setup openvpn in ${SETUP_HOME} .............."
bash -x "${SETUP_HOME}/configure.sh"