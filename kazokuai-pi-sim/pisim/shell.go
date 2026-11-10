package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
)

const (
	enrolledEnv = "PISIM_ENROLLED"
	piHostname  = "kazokuai"
)

func init() {
	runtime.LockOSThread()
}

func alreadyEnrolled() bool {
	b, err := os.ReadFile("/proc/self/status")
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(b), "\n") {
		if v, ok := strings.CutPrefix(line, "Seccomp_filters:"); ok {
			n, _ := strconv.Atoi(strings.TrimSpace(v))
			return n > 0 && os.Getenv(enrolledEnv) == "1"
		}
	}
	return false
}

func enter() error {
	if alreadyEnrolled() {
		return nil
	}

	conn, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: enrollSock, Net: "unix"})
	if err != nil {
		return fmt.Errorf("電話機のラズパイ(pisim daemon)が動いていません")
	}
	defer conn.Close()

	if err := syscall.Unshare(syscall.CLONE_NEWNS | syscall.CLONE_NEWUTS); err != nil {
		return fmt.Errorf("名前空間を分けられません: %w", err)
	}
	if err := syscall.Mount("", "/", "", syscall.MS_REC|syscall.MS_SLAVE, ""); err != nil {
		return fmt.Errorf("マウントを分けられません: %w", err)
	}
	if err := syscall.Sethostname([]byte(piHostname)); err != nil {
		return fmt.Errorf("ホスト名を %s にできません: %w", piHostname, err)
	}
	if err := enterNetns(); err != nil {
		return err
	}
	if err := hideOtherChipDevices(); err != nil {
		return err
	}
	shareWSLgDisplay()
	for _, m := range bindMounts {
		if _, err := os.Stat(m.target); err != nil {
			continue
		}
		if err := syscall.Mount(m.source, m.target, "", syscall.MS_BIND, ""); err != nil {
			return fmt.Errorf("%s を重ねられません: %w", m.target, err)
		}
	}

	lfd, err := installFilter()
	if err != nil {
		return err
	}
	_, _, err = conn.WriteMsgUnix([]byte("enroll"), syscall.UnixRights(lfd), nil)
	syscall.Close(lfd)
	if err != nil {
		return err
	}

	ack := make([]byte, 2)
	if _, err := conn.Read(ack); err != nil || string(ack) != "ok" {
		return errors.New("電話機のラズパイが受け付けませんでした")
	}
	os.Setenv(enrolledEnv, "1")
	return nil
}

func hideOtherChipDevices() error {
	ents, err := os.ReadDir("/dev")
	if err != nil {
		return nil
	}
	for _, e := range ents {
		path := filepath.Join("/dev", e.Name())
		if path == chipPath {
			continue
		}
		var st syscall.Stat_t
		if syscall.Stat(path, &st) != nil || st.Mode&syscall.S_IFMT != syscall.S_IFCHR || st.Rdev != chipMajor<<8|chipMinor {
			continue
		}
		if err := syscall.Mount("/dev/null", path, "", syscall.MS_BIND, ""); err != nil {
			return fmt.Errorf("%s を隠せません: %w", path, err)
		}
	}
	return nil
}

func shareWSLgDisplay() {
	const wslgX11, x11 = "/mnt/wslg/.X11-unix", "/tmp/.X11-unix"
	if _, err := os.Stat(x11 + "/X0"); err == nil {
		return
	}
	if _, err := os.Stat(wslgX11 + "/X0"); err != nil {
		return
	}
	os.MkdirAll(x11, 0o1777)
	if syscall.Mount(wslgX11, x11, "", syscall.MS_BIND, "") == nil {
		syscall.Mount("", x11, "", syscall.MS_BIND|syscall.MS_REMOUNT|syscall.MS_RDONLY, "")
	}
}

func dropTo(uid, gid int, groups []int) error {
	if os.Geteuid() != 0 {
		return nil
	}
	if groups != nil {
		if err := syscall.Setgroups(groups); err != nil {
			return err
		}
	}
	if err := syscall.Setresgid(gid, gid, gid); err != nil {
		return err
	}
	return syscall.Setresuid(uid, uid, uid)
}

func runShell(argv0 string, args []string) error {
	uid, gid := os.Getuid(), os.Getgid()

	if err := enter(); err != nil {
		fmt.Fprintf(os.Stderr, "pisim: %v。ふつうの bash で入ります(GPIO は使えません)。\n", err)
	}
	if err := dropTo(uid, gid, nil); err != nil {
		return err
	}

	name := "bash"
	if strings.HasPrefix(argv0, "-") {
		name = "-bash"
	}
	return syscall.Exec("/bin/bash", append([]string{name}, args...), os.Environ())
}

func runExec(args []string) error {
	var who string
	if len(args) >= 2 && args[0] == "--user" {
		who = args[1]
		args = args[2:]
	}
	if len(args) > 0 && args[0] == "--" {
		args = args[1:]
	}
	if len(args) == 0 {
		return errors.New("使い方: pisim exec [--user 名前] -- コマンド [引数…]")
	}

	uid, gid := os.Getuid(), os.Getgid()
	var groups []int
	if who != "" {
		u, err := user.Lookup(who)
		if err != nil {
			return err
		}
		uid, _ = strconv.Atoi(u.Uid)
		gid, _ = strconv.Atoi(u.Gid)
		gids, _ := u.GroupIds()
		for _, g := range gids {
			n, _ := strconv.Atoi(g)
			groups = append(groups, n)
		}
		os.Setenv("HOME", u.HomeDir)
		os.Setenv("USER", u.Username)
		os.Setenv("LOGNAME", u.Username)
	}

	if err := enter(); err != nil {
		return err
	}
	if err := dropTo(uid, gid, groups); err != nil {
		return err
	}

	path, err := exec.LookPath(args[0])
	if err != nil {
		return err
	}
	return syscall.Exec(path, args, os.Environ())
}

func isShellName(argv0 string) bool {
	base := filepath.Base(strings.TrimPrefix(argv0, "-"))
	return strings.TrimPrefix(base, "-") == "pisim-shell"
}
