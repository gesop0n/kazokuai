package main

import (
	"fmt"
	"log"
	"os"
)

func main() {
	log.SetFlags(log.Ltime)

	if isShellName(os.Args[0]) {
		if err := runShell(os.Args[0], os.Args[1:]); err != nil {
			fmt.Fprintln(os.Stderr, "pisim-shell:", err)
			os.Exit(1)
		}
		return
	}

	if len(os.Args) < 2 {
		usage()
	}

	var err error
	switch os.Args[1] {
	case "daemon":
		err = runDaemon(os.Args[2:])
	case "shell":
		err = runShell("", os.Args[2:])
	case "exec":
		err = runExec(os.Args[2:])
	case "net":
		err = runNet(os.Args[2:])
	case "status":
		err = printStatus()
	default:
		usage()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "pisim:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `使い方:
  pisim daemon [--config /etc/kazokuai-pisim.conf]   電話機のラズパイを動かす(root)
  pisim shell                                        電話機の中で bash を開く
  pisim exec [--user 名前] -- コマンド [引数…]        電話機の中でコマンドを動かす
  pisim net up|down                                  電話機の eth0 と wlan0 を作る・消す(root)
  pisim status                                       GPIO と部品の状態を出す`)
	os.Exit(2)
}
