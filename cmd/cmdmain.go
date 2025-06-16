package main

import (
	"os"
	"path/filepath"

	"github.com/kubecombo/kube-combo/cmd/controller"
	"github.com/kubecombo/kube-combo/cmd/pinger"
)

const (
	CmdController = "controller"
	CmdPinger     = "pinger"
)

func main() {
	cmd := filepath.Base(os.Args[0])
	switch cmd {
	case CmdController:
		controller.CmdMain()
	case CmdPinger:
		pinger.CmdMain()
	default:
		println("unknown command:", cmd)
	}
}
