#!/bin/bash
set -eux
# usage example:
# site1
# /connection.sh refresh \
# moon-sun pubkey 2 default moon.vpn.gw.com 172.19.0.101 10.1.0.0/24 sun.vpn.gw.com 172.19.0.102 10.2.0.0/24,\
# moon-mars pubkey 2 default moon.vpn.gw.com 172.19.0.101 10.1.0.0/24 mars.vpn.gw.com 172.19.0.103 10.3.0.0/24

# site2
# /connection.sh refresh \
# sun-moon pubkey 2 default sun.vpn.gw.com 172.19.0.102 10.2.0.0/24 moon.vpn.gw.com 172.19.0.101 10.1.0.0/24,

# make it runable in any directory
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
		cp "${HOSTS}" hosts.j2
		cat "${TEMPLATE_HOSTS}" >>hosts.j2
	fi
	# prepare swanctl.conf.j2
	if [ ! -f swanctl.conf.j2 ]; then
		cp "${TEMPLATE_SWANCTL_CONF}" swanctl.conf.j2
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
	printf "connections: \n" >"${CONNECTIONS_YAML}"
	IFS=',' read -r -a array <<<"${connections}"
	for connection in "${array[@]}"; do
		# echo "show connection: ${connection}"
		IFS=' ' read -r -a conn <<<"${connection}"
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
		} >>"${CONNECTIONS_YAML}"
	done
	# 3. generate hosts and swanctl.conf
	# use j2 to generate hosts and swanctl.conf
	j2 hosts.j2 "${CONNECTIONS_YAML}" -o "${HOSTS}"
	j2 swanctl.conf.j2 "${CONNECTIONS_YAML}" -o "${CONF}"
	j2 "${TEMPLATE_CHECK}" "${CONNECTIONS_YAML}" -o "${CHECK_SCRIPT}"
	chmod +x "${CHECK_SCRIPT}"

	# 5. /etc/host-init-strongswan for static pod
	host-init-cache
}

function host-init-cache() {
	if [ -d "/etc/host-init-strongswan" ]; then
		CACHE_HOME=/etc/host-init-strongswan
		CONF_HOME=/etc/swanctl
		HOSTS_HOME=/etc/hosts

		# if /etc/host-init-strongswan directory is exist, skip running ipsecvpn here
		# it will be run in k8s static pod later
		echo "/etc/host-init-strongswan cache directory exist .............."

		# clean up old ipsecvpn certs and conf cache dir /etc/host-init-strongswan to refresh
		rm -fr "/etc/host-init-strongswan/*"
		# echo "show ${CONF_HOME} files..........."
		# ls -lR "${CONF_HOME}"

		# copy all ipsecvpn server need file from /etc/ipsecvpn to /etc/host-init-strongswan
		# fix:// todo:// wait connection is ready and then copy it
		\cp -r "${CONF_HOME}/private" "${CACHE_HOME}/"
		\cp -r "${CONF_HOME}/x509" "${CACHE_HOME}/"
		\cp -r "${CONF_HOME}/x509ca" "${CACHE_HOME}/"

		\cp "${CONF_HOME}/swanctl.conf" "${CACHE_HOME}/"

		\cp "${HOSTS_HOME}" "${CACHE_HOME}/"

		# echo "show /etc/host-init-strongswan files .............."
		# ls -lR "${CACHE_HOME}/"

		# ls -l /static-pod-start.sh
		\cp /static-pod-start.sh /etc/host-init-strongswan/static-pod-start.sh

		# echo "show /etc/host-init-strongswan/static-pod-start.sh .............."
		# cat /etc/host-init-strongswan/static-pod-start.sh

		# echo "deploy static pod /etc/kubernetes/manifests .............."
		\cp "/static-strongswan.yaml" "/etc/kubernetes/manifests"
	else
		# only run /usr/sbin/swanctl --load-all while /usr/sbin/charon-systemd is running, or
		# /usr/sbin/swanctl --load-all
		# connecting to 'unix:///var/run/charon.vici' failed: No such file or directory

		# 4. reload strongswan connections
		# show version
		# /usr/sbin/swanctl --help
		echo "load strongswan connections"
		/usr/sbin/swanctl --load-all | grep successfully
	# /usr/sbin/swanctl --list-conns
	fi
}

if [ $# -eq 0 ]; then
	echo "Usage: $0 [init|refresh]"
	exit 1
fi
connections=${*:2:${#}}
opt=$1
case ${opt} in
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
