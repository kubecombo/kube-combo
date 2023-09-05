#!/bin/bash
set -euo pipefail

CONF=/etc/swanctl/swanctl.conf
CONNECTIONS_YAML=connections.yaml
HOSTS=/etc/hosts
TEMPLATE_HOSTS=template-hosts.j2
TEMPLATE_SWANCTL_CONF=template-swanctl.conf.j2
TEMPLATE_CHECK=template-check.j2
CHECK_SCRIPT=check

function init() {
    # prepare hosts.j2
    if [ ! -f hosts.j2 ]; then
        cp $HOSTS  hosts.j2
        cat $TEMPLATE_HOSTS >> hosts.j2
    fi
    # prepare swanctl.conf.j2
    if [ ! -f swanctl.conf.j2 ]; then
        mv $CONF swanctl.conf.orig
        cp $TEMPLATE_SWANCTL_CONF swanctl.conf.j2
    fi

    #
    # configure ca
    cp /etc/ipsec/certs/ca.crt /etc/swanctl/x509ca
    cp /etc/ipsec/certs/tls.key /etc/swanctl/private
    cp /etc/ipsec/certs/tls.crt /etc/swanctl/x509

}

function refresh() {
    # 1. init
    init
    # 2. refresh connections
    # format connections into connection.yaml
    printf "connections: \n" > $CONNECTIONS_YAML
    IFS=',' read -r -a array <<< "${connections}"
    for connection in "${array[@]}"
    do
        # echo "show connection: ${connection}"
        IFS=' ' read -r -a conn <<< "${connection}"
        name=${conn[0]}
        auth=${conn[1]}
        ikeVersion=${conn[2]}
        proposal=${conn[3]}
        localCN=${conn[4]}
        localPublicIp=${conn[5]}
        localPrivateCidrs=${conn[6]}
        remoteCN=${conn[7]}
        remotePublicIp=${conn[8]}
        remotePrivateCidrs=${conn[9]}
        { 
        printf "  - name: %s\n" "${name}"
        printf "    auth: %s\n" "${auth}"
        printf "    ikeVersion: %s\n" "${ikeVersion}"
        printf "    proposals: %s\n" "${proposal}"
        printf "    localCN: %s\n" "${localCN}"
        printf "    localPublicIp: %s\n" "${localPublicIp}"
        printf "    localPrivateCidrs: %s\n" "${localPrivateCidrs}"
        printf "    remoteCN: %s\n" "${remoteCN}"
        printf "    remotePublicIp: %s\n" "${remotePublicIp}"
        printf "    remotePrivateCidrs: %s\n" "${remotePrivateCidrs}"
        } >> $CONNECTIONS_YAML
    done
    # 3. generate hosts and swanctl.conf
    # use j2 to generate hosts and swanctl.conf
    j2 hosts.j2 $CONNECTIONS_YAML -o $HOSTS
    j2 swanctl.conf.j2 $CONNECTIONS_YAML -o $CONF
    j2 $TEMPLATE_CHECK $CONNECTIONS_YAML -o $CHECK_SCRIPT
    chmod +x $CHECK_SCRIPT

    # 4. reload strongswan connections
    /usr/sbin/swanctl --load-all
}

if [ $# -eq 0 ]; then
    echo "Usage: $0 [init|refresh]"
    exit 1
fi
connections=${*:2:${#}}
opt=$1
case $opt in
 init)
        init
        ;;
 refresh)
        refresh "${connections}"
        ;;
 *)
        echo "Usage: $0 [init|refresh]"
        exit 1
        ;;
esac
