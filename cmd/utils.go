package main

import (
	"fmt"
	"log"
	"net"
	"os"
	"strconv"

	"k8s.io/klog/v2"
)

func LogFatalAndExit(err error, format string, a ...any) {
	klog.ErrorS(err, fmt.Sprintf(format, a...))
	klog.FlushAndExit(klog.ExitFlushTimeout, 1)
}

func InitLogFilePerm(moduleName string, perm os.FileMode) {
	logPath := "/var/log/kube-ovn/" + moduleName + ".log"
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

func JoinHostPort(host string, port int32) string {
	return net.JoinHostPort(host, strconv.FormatInt(int64(port), 10))
}

func UDPConnectivityListen(endpoint string) error {
	listenAddr, err := net.ResolveUDPAddr("udp", endpoint)
	if err != nil {
		err := fmt.Errorf("failed to resolve udp addr: %w", err)
		klog.Error(err)
		return err
	}

	conn, err := net.ListenUDP("udp", listenAddr)
	if err != nil {
		err := fmt.Errorf("failed to listen udp address: %w", err)
		klog.Error(err)
		return err
	}

	buffer := make([]byte, 1024)

	go func() {
		for {
			_, clientAddr, err := conn.ReadFromUDP(buffer)
			if err != nil {
				klog.Error(err)
				continue
			}

			_, err = conn.WriteToUDP([]byte("health check"), clientAddr)
			if err != nil {
				klog.Error(err)
				continue
			}
		}
	}()

	return nil
}

func TCPConnectivityListen(endpoint string) error {
	listener, err := net.Listen("tcp", endpoint)
	if err != nil {
		err := fmt.Errorf("failed to listen %s, %w", endpoint, err)
		klog.Error(err)
		return err
	}

	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				klog.Error(err)
				continue
			}
			_ = conn.Close()
		}
	}()

	return nil
}
