package main

import (
	"os"
	"path/filepath"

	"github.com/kubecombo/kube-combo/cmd/manager"
	"github.com/kubecombo/kube-combo/cmd/pinger"
)

const (
	CmdManager = "manager"
	CmdPinger  = "pinger"
)

func main() {
	cmd := filepath.Base(os.Args[0])
	switch cmd {
	case CmdManager:
		manager.CmdMain()
	case CmdPinger:
		pinger.CmdMain()
	default:
		println("unknown command:", cmd)
	}
}
