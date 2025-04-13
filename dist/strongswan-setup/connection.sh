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
CONNECTIONS_YAML=/etc/host-init-strongswan/connections.yaml
IPSEC_HOSTS=/etc/hosts.ipsec
TEMPLATE_HOSTS=template-hosts.j2
TEMPLATE_CHECK=template-check.j2
CHECK_SCRIPT=check
DefaultPSK=""

# IPSEC_VPN_IMAGE set the static pod image
K8S_MANIFESTS_PATH=${K8S_MANIFESTS_PATH:-/etc/kubernetes/manifests}

function init() {
	# prepare hosts.j2
	if [ ! -f hosts.j2 ]; then
		cat "${TEMPLATE_HOSTS}" >>hosts.j2
	fi
}

function refresh-x509() {
	# 1. init
	init

	# 2. prepare swanctl.conf.j2
	TEMPLATE_SWANCTL_CONF=template-swanctl.x509.conf.j2
	cp "${TEMPLATE_SWANCTL_CONF}" swanctl.conf.j2

	# configure ca
	cp /etc/ipsec/certs/ca.crt /etc/swanctl/x509ca
	cp /etc/ipsec/certs/tls.key /etc/swanctl/private
	cp /etc/ipsec/certs/tls.crt /etc/swanctl/x509

	# 3. refresh connections
	# format connections into connection.yaml
	printf "connections: \n" >"${CONNECTIONS_YAML}"
	IFS=':' read -r -a array <<<"${connections}"
	for connection in "${array[@]}"; do
		# echo "show connection: ${connection}"
		IFS=' ' read -r -a conn <<<"${connection}"
		name=${conn[0]}
		auth=${conn[1]}
		ikeVersion=${conn[2]}
		ikeProposals=${conn[3]}
		localCN=${conn[4]}
		localEIP=${conn[5]}
		localPrivateCidrs=${conn[6]}
		remoteCN=${conn[7]}
		remoteEIP=${conn[8]}
		remotePrivateCidrs=${conn[9]}
		{
			printf "  - name: %s\n" "${name}"
			printf "    auth: %s\n" "${auth}"
			printf "    ikeVersion: %s\n" "${ikeVersion}"
			printf "    ikeProposals: %s\n" "${ikeProposals}"
			printf "    localCN: %s\n" "${localCN}"
			printf "    localEIP: %s\n" "${localEIP}"
			printf "    localPrivateCidrs: %s\n" "${localPrivateCidrs}"
			printf "    remoteCN: %s\n" "${remoteCN}"
			printf "    remoteEIP: %s\n" "${remoteEIP}"
			printf "    remotePrivateCidrs: %s\n" "${remotePrivateCidrs}"
		} >>"${CONNECTIONS_YAML}"
	done
	# 4. generate hosts and swanctl.conf
	# use j2 to generate hosts and swanctl.conf
	j2 hosts.j2 "${CONNECTIONS_YAML}" -o "${IPSEC_HOSTS}"
	if [ ! -e "/etc/hosts.ori" ]; then
		# backup hosts
		cp /etc/hosts /etc/hosts.ori
	fi
	cat /etc/hosts.ori >/etc/hosts
	cat "${IPSEC_HOSTS}" >>/etc/hosts
	j2 swanctl.conf.j2 "${CONNECTIONS_YAML}" -o "${CONF}"
	j2 "${TEMPLATE_CHECK}" "${CONNECTIONS_YAML}" -o "${CHECK_SCRIPT}"
	chmod +x "${CHECK_SCRIPT}"

	# 5. /etc/host-init-strongswan for static pod
	host-init-cache
}

function refresh-psk() {
	# 2. prepare swanctl.conf.j2
	TEMPLATE_SWANCTL_CONF=template-swanctl.psk.conf.j2
	cp "${TEMPLATE_SWANCTL_CONF}" swanctl.conf.j2

	# 3. refresh connections
	# format connections into connection.yaml
	printf "connections: \n" >"${CONNECTIONS_YAML}"
	IFS=':' read -r -a array <<<"${connections}"
	for connection in "${array[@]}"; do
		# echo "show connection: ${connection}"
		IFS=' ' read -r -a conn <<<"${connection}"
		length=${#conn[@]}  # 13
		name=${conn[0]}
		auth=${conn[1]}
		ikeVersion=${conn[2]}
		ikeProposals=${conn[3]}
		localVIP=${conn[4]}
		localEIP=${conn[5]}
		localPrivateCidrs=${conn[6]}
		remoteEIP=${conn[7]}
		remotePrivateCidrs=${conn[8]}
		DefaultPSK=$(echo "${conn[9]}" | base64 -d)
		espProposals=${conn[10]}
		localVipGateway=""
		localGatewayNic=""
		if [ ${length} -eq 13 ]; then
			localVipGateway=${conn[11]}
			localGatewayNic=${conn[12]}
		fi
		{
			printf "  - name: %s\n" "${name}"
			printf "    auth: %s\n" "${auth}"
			printf "    ikeVersion: %s\n" "${ikeVersion}"
			printf "    ikeProposals: %s\n" "${ikeProposals}"
			printf "    localVIP: %s\n" "${localVIP}"
			printf "    localEIP: %s\n" "${localEIP}"
			printf "    localPrivateCidrs: %s\n" "${localPrivateCidrs}"
			printf "    remoteEIP: %s\n" "${remoteEIP}"
			printf "    remotePrivateCidrs: %s\n" "${remotePrivateCidrs}"
			printf "    espProposals: %s\n" "${espProposals}"
			printf "    localVipGateway: %s\n" "${localVipGateway}"
			printf "    localGatewayNic: %s\n" "${localGatewayNic}"
		} >>"${CONNECTIONS_YAML}"
	done
	printf "DefaultPSK: %s\n" "${DefaultPSK}" >>"${CONNECTIONS_YAML}"

	echo "show ${CONNECTIONS_YAML} .............."
	cat "${CONNECTIONS_YAML}"

	j2 "${TEMPLATE_CHECK}" "${CONNECTIONS_YAML}" -o "${CHECK_SCRIPT}"
	chmod +x "${CHECK_SCRIPT}"
	j2 swanctl.conf.j2 "${CONNECTIONS_YAML}" -o "${CONF}"
	# 5. /etc/host-init-strongswan for static pod
	host-init-cache
}

function host-init-cache() {
	if [ -d "/etc/host-init-strongswan" ]; then
		CACHE_HOME=/etc/host-init-strongswan
		CONF_HOME=/etc/swanctl
		# if /etc/host-init-strongswan directory is exist, skip running ipsecvpn here
		# it will be run in k8s static pod later
		echo "/etc/host-init-strongswan cache directory exist .............."

		# clean up old ipsecvpn certs and conf cache dir /etc/host-init-strongswan to load
		rm -fr "/etc/host-init-strongswan/*"
		# echo "show ${CONF_HOME} files..........."
		# ls -lR "${CONF_HOME}"

		# copy all ipsecvpn server need file from /etc/ipsecvpn to /etc/host-init-strongswan
		# fix:// todo:// wait connection is ready and then copy it
		\cp -r "${CONF_HOME}/private" "${CACHE_HOME}/"
		\cp -r "${CONF_HOME}/x509" "${CACHE_HOME}/"
		\cp -r "${CONF_HOME}/x509ca" "${CACHE_HOME}/"

		\cp "${CONF_HOME}/swanctl.conf" "${CACHE_HOME}/"

		\cp "${CHECK_SCRIPT}" "${CACHE_HOME}/"
		# echo "show /etc/host-init-strongswan files .............."
		# ls -lR "${CACHE_HOME}/"

		# ls -l /static-pod-start.sh
		\cp /static-pod-start.sh /etc/host-init-strongswan/static-pod-start.sh

		# echo "show /etc/host-init-strongswan/static-pod-start.sh .............."
		# cat /etc/host-init-strongswan/static-pod-start.sh

		echo "deploy static pod ${K8S_MANIFESTS_PATH} .............."
		sed 's|IPSEC_VPN_IMAGE|'"${IPSEC_VPN_IMAGE}"'|' -i "/static-strongswan.yaml"
		\cp "/static-strongswan.yaml" "${K8S_MANIFESTS_PATH}"
	else
		# only run /usr/sbin/swanctl --load-all while /usr/sbin/charon-systemd is running, or
		# /usr/sbin/swanctl --load-all
		# connecting to 'unix:///var/run/charon.vici' failed: No such file or directory

		# 4. reload strongswan connections
		# show version
		# /usr/sbin/swanctl --help
		echo "load: "
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
refresh-x509)
	refresh-x509 "${connections}"
	;;
refresh-psk)
	refresh-psk "${connections}"
	;;
*)
	echo "Usage: $0 [init|refresh-x509|refresh-psk]"
	exit 1
	;;
esac
