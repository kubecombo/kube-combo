package main

import (
	"os"
	"path/filepath"

	"github.com/kubecombo/kube-combo/cmd/controller"
	"github.com/kubecombo/kube-combo/cmd/debugger"
	"github.com/kubecombo/kube-combo/cmd/pinger"
)

const (
	CmdController = "controller"
	CmdPinger     = "pinger"
	CmdDebugger   = "debugger"
)

func main() {
	cmd := filepath.Base(os.Args[0])
	switch cmd {
	case CmdController:
		controller.CmdMain()
	case CmdPinger:
		pinger.CmdMain()
	case CmdDebugger:
		debugger.CmdMain()
	default:
		println("unknown command:", cmd)
	}
}
