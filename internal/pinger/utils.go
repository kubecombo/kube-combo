package pinger

import (
	"fmt"
	"log"
	"net"
	"os"
	"strconv"
	"strings"
	"time"

	"k8s.io/klog/v2"
)

const (
	ProtocolTCP  = "tcp"
	ProtocolUDP  = "udp"
	ProtocolSCTP = "sctp"

	ProtocolIPv4 = "IPv4"
	ProtocolIPv6 = "IPv6"
	ProtocolDual = "Dual"
)

func LogFatalAndExit(err error, format string, a ...any) {
	klog.ErrorS(err, fmt.Sprintf(format, a...))
	klog.FlushAndExit(klog.ExitFlushTimeout, 1)
}

func TCPConnectivityCheck(endpoint string) error {
	conn, err := net.DialTimeout("tcp", endpoint, 3*time.Second)
	if err != nil {
		klog.Error(err)
		return err
	}

	_ = conn.Close()

	return nil
}

func UDPConnectivityCheck(endpoint string) error {
	udpAddr, err := net.ResolveUDPAddr("udp", endpoint)
	if err != nil {
		err := fmt.Errorf("failed to resolve %s, %w", endpoint, err)
		klog.Error(err)
		return err
	}

	conn, err := net.DialUDP("udp", nil, udpAddr)
	if err != nil {
		klog.Error(err)
		return err
	}

	defer conn.Close()

	if err := conn.SetReadDeadline(time.Now().Add(3 * time.Second)); err != nil {
		klog.Error(err)
		return err
	}

	_, err = conn.Write([]byte("health check"))
	if err != nil {
		err := fmt.Errorf("failed to send udp packet, %w", err)
		klog.Error(err)
		return err
	}

	buffer := make([]byte, 1024)
	_, err = conn.Read(buffer)
	if err != nil {
		err := fmt.Errorf("failed to read udp packet from remote, %w", err)
		klog.Error(err)
		return err
	}

	return nil
}

func JoinHostPort(host string, port int32) string {
	return net.JoinHostPort(host, strconv.FormatInt(int64(port), 10))
}

func CheckProtocol(address string) string {
	if address == "" {
		return ""
	}

	ips := strings.Split(address, ",")
	if len(ips) == 2 {
		IP1 := net.ParseIP(strings.Split(ips[0], "/")[0])
		IP2 := net.ParseIP(strings.Split(ips[1], "/")[0])
		if IP1.To4() != nil && IP2.To4() == nil && IP2.To16() != nil {
			return ProtocolDual
		}
		if IP2.To4() != nil && IP1.To4() == nil && IP1.To16() != nil {
			return ProtocolDual
		}
		err := fmt.Errorf("invalid address %q", address)
		klog.Error(err)
		return ""
	}

	address = strings.Split(address, "/")[0]
	ip := net.ParseIP(address)
	if ip.To4() != nil {
		return ProtocolIPv4
	} else if ip.To16() != nil {
		return ProtocolIPv6
	}

	// cidr format error
	err := fmt.Errorf("invalid address %q", address)
	klog.Error(err)
	return ""
}

func InitLogFilePerm(moduleName string, perm os.FileMode) {
	logPath := "/var/log/kube-combo/" + moduleName + ".log"
	if _, err := os.Stat(logPath); os.IsNotExist(err) {
		f, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, perm)
		if err != nil {
			log.Fatalf("failed to create log file: %v", err)
		}
		f.Close()
	} else {
		if err := os.Chmod(logPath, perm); err != nil {
			log.Fatalf("failed to chmod log file: %v", err)
		}
	}
}
