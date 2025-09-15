package util

// const for pinger
const (
	ProtocolTCP  = "tcp"
	ProtocolUDP  = "udp"
	ProtocolSCTP = "sctp"

	ProtocolIPv4 = "IPv4"
	ProtocolIPv6 = "IPv6"
	ProtocolDual = "Dual"
)

// const for vpngw_controller
const (
	DebuggerName = "debug"
	PingerName   = "ping"

	// custom script mount directory
	ScriptsPath = "/scripts"
	// an inspection task list mounting directory
	RunAtPath = "/tasks"

	DebuggerStartCMD = "/debugger-start.sh"
	PingerStartCMD   = "/pinger-start.sh"

	// WorkloadTypePod is the workload type for pod
	WorkloadTypePod = "pod"
	// WorkloadTypeDaemonset is the workload type for daemonset
	WorkloadTypeDaemonset = "daemonset"
	// debugger env
	Subnet = "SUBNET"
	// pinger env
	Ping    = "PING"
	TcpPing = "TCP_PING"
	UdpPing = "UDP_PING"
	Dns     = "DNS"

	EnableMetrics = "ENABLE_METRICS"

	// service account
	ServiceAccountName = "kube-ovn-app"
)

// volume mounts
const (
	// volume path and name
	VarRunOpenvswitch = "/var/run/openvswitch"
	OpenvswitchName   = "host-run-ovs"

	VarRunOvn = "/var/run/ovn"
	OvnName   = "host-run-ovn"

	EtcOpenvswitch    = "/etc/openvswitch"
	OpenvswitchConfig = "host-config-openvswitch"

	VarLogOpenvswitch = "/var/log/openvswitch"
	OpenvswitchLog    = "host-log-openvswitch"

	VarLogOvn = "/var/log/ovn"
	OvnLog    = "host-log-ovn"

	VarLogKubeOvn = "/var/log/kube-ovn"
	KubeOvnLog    = "host-log-kube-ovn"

	VarLogKubeCombo = "/var/log/kube-combo"
	KubeComboLog    = "host-log-kube-combo"

	LocalTime     = "/etc/localtime"
	LocalTimeName = "localtime"

	VarRunTls = "/var/run/tls"
	TlsName   = "kube-ovn-tls"
)

const (
	// enable sys system
	EtcSystemdPath         = "/etc/systemd/system"
	EtcSystemdName         = "etc-systemd"
	RunSystemdPath         = "/run/systemd/system"
	RunSystemdName         = "run-systemd"
	VarRunSystemdPath      = "/var/run/systemd/system"
	VarRunSystemdName      = "var-run-systemd"
	UsrLocalLibSystemdPath = "/usr/local/lib/systemd/system"
	UsrLocalLibSystemdName = "usr-local-lib-systemd"
	UsrLibSystemdPath      = "/usr/lib/systemd/system"
	UsrLibSystemdName      = "usr-lib-systemd"
	LibSystemdPath         = "/lib/systemd/system"
	LibSystemdName         = "lib-systemd"

	// enable sys *
	CgroupPath  = "/sys/fs/cgroup"
	CgroupName  = "cgroup"
	JournalPath = "/var/log/journal"
	JournalName = "var-log-journal"
)

// const for provider_kube_ovn
const (
	KubeovnLogicalSwitchAnnotation = "ovn.kubernetes.io/logical_switch"
	KubeovnIngressRateAnnotation   = "ovn.kubernetes.io/ingress_rate"
	KubeovnEgressRateAnnotation    = "ovn.kubernetes.io/egress_rate"
)

// const for keepalived_controller
const (
	RouterIDLabel = "router-id"
	SubnetLabel   = "subnet"
)

// const for vpngw_controller
const (
	VpnGwLabel = "vpn-gw"

	// ssl vpn openvpn
	SslVpnServer = "ssl-vpn"

	// statefulset ssl vpn pod start up command
	SslVpnStsCMD = "/etc/openvpn/setup/configure.sh"

	// daemonset ssl vpn pod start up command
	SslVpnDsCMD = "/etc/openvpn/setup/daemonset-start.sh"

	// cache path from ds openvpn to k8s static pod openvpn
	SslVpnHostCachePath = "/etc/host-init-openvpn"
	SslVpnCacheName     = "openvpn-cache"

	// ds pod use this volume to copy static pod yaml to kubelet
	K8sManifests = "k8s-manifests"

	EnableSslVpnLabel = "enable-ssl-vpn"

	K8sManifestsPathKey = "K8S_MANIFESTS_PATH"

	// vpn gw pod env
	SslVpnProtoKey      = "SSL_VPN_PROTO"
	SslVpnPortKey       = "SSL_VPN_PORT"
	SslVpnCipherKey     = "SSL_VPN_CIPHER"
	SslVpnAuthKey       = "SSL_VPN_AUTH"
	SslVpnSubnetCidrKey = "SSL_VPN_SUBNET_CIDR"
	SslVpnImageKey      = "SSL_VPN_IMAGE"

	// ipsec vpn strongswan
	IPSecVpnServer = "ipsec-vpn"

	IPSecVpnLocalPortKey  = "ipsec-local"
	IPSecVpnRemotePortKey = "ipsec-remote"

	// statefulset ipsec vpn pod start up command
	IPSecVpnStsCMD = "/usr/sbin/charon-systemd"

	IPSecRefreshConnectionX509Template = "/connection.sh refresh-x509 %s"
	IPSecRefreshConnectionPSKTemplate  = "/connection.sh refresh-psk %s"

	// cache path from ds ipsec vpn to k8s static pod ipsecvpn
	IPSecVpnHostCachePath = "/etc/host-init-strongswan"
	IPSecVpnCacheName     = "strongswan-cache"

	EnableIPSecVpnLabel = "enable-ipsec-vpn"

	IPSecBootPcPortKey = "bootpc"
	IPSecIsakmpPortKey = "isakmp"
	IPSecNatPortKey    = "nat"

	IPSecProto = "UDP"

	IPSecVpnImageKey = "IPSEC_VPN_IMAGE"
	// IPSecRemoteAddrsKey = "IPSEC_REMOTE_ADDRS"
	// IPSecRemoteTsKey    = "IPSEC_REMOTE_TS"
)

// keepalived
const (
	KeepalivedVipKey          = "KEEPALIVED_VIP"
	KeepalivedVirtualRouterID = "KEEPALIVED_VIRTUAL_ROUTER_ID"
	KeepalivedNicKey          = "KEEPALIVED_NIC"
	KeepalivedStartUpCMD      = "/configure.sh"
	KeepAlivedServer          = "keepalived"
)

// const for debugger
const (
	DetectionScriptsPath = "/runAt"
	EIS_API_SVC          = "eis.eis.svc.cluster.local"
	EIS_API_PORT         = "8361"
	LOG_LEVEL            = "info"
	LOG_FLAG             = "false"
	LOG_FILE             = "/var/log/debugger.log"
)
