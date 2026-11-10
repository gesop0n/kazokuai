package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

const (
	netnsName = "kazokuai"
	netnsPath = "/run/netns/" + netnsName
	hostIf    = "pisim0"
	apIf      = "pisimap0"
	sysMnt    = runDir + "/sysmnt"
	wifiError = runDir + "/wifi-error"
	moduleDir = "/usr/local/lib/pisim/modules"

	wiredHost = "10.77.0.1"
	wiredPi   = "10.77.0.2"
	wifiHost  = "10.78.0.1"
)

func runCmd(name string, args ...string) error {
	out, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s %s: %v %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return nil
}

func runNet(args []string) error {
	if len(args) != 1 || (args[0] != "up" && args[0] != "down") {
		return fmt.Errorf("使い方: pisim net up|down")
	}
	cfg, err := LoadConfig(configPath)
	if err != nil {
		return err
	}
	if args[0] == "down" {
		netDown()
		return nil
	}
	return netUp(cfg)
}

func netDown() {
	exec.Command("ip", "netns", "delete", netnsName).Run()
	exec.Command("ip", "link", "delete", hostIf).Run()
	exec.Command("nft", "delete", "table", "ip", "kazokuai").Run()
}

func netUp(cfg Config) error {
	os.MkdirAll(runDir, 0o755)
	netDown()
	time.Sleep(300 * time.Millisecond)

	ns := []string{"-n", netnsName}
	steps := [][]string{
		{"netns", "add", netnsName},
		{"link", "add", hostIf, "type", "veth", "peer", "name", "eth0", "netns", netnsName},
		{"addr", "add", wiredHost + "/24", "dev", hostIf},
		{"link", "set", hostIf, "up"},
		append(ns, "link", "set", "lo", "up"),
		append(ns, "link", "set", "eth0", "address", boardMAC(0)),
		append(ns, "addr", "add", wiredPi+"/24", "dev", "eth0"),
		append(ns, "link", "set", "eth0", "up"),
		append(ns, "route", "add", "default", "via", wiredHost),
	}
	for _, s := range steps {
		if err := runCmd("ip", s...); err != nil {
			return err
		}
	}

	if err := os.WriteFile("/proc/sys/net/ipv4/ip_forward", []byte("1\n"), 0o644); err != nil {
		log.Printf("ip_forward を有効にできませんでした: %v", err)
	}
	if err := runCmd("ip", "netns", "exec", netnsName, "sysctl", "-qw", "net.ipv4.ping_group_range=0 2147483647"); err != nil {
		log.Printf("電話機で ping を使えるようにできませんでした: %v", err)
	}
	if err := natRules(); err != nil {
		return err
	}

	if cfg.Wifi {
		if err := wifiUp(); err != nil {
			log.Printf("無線の wlan0 を作れませんでした(有線の eth0 だけで動きます): %v", err)
			os.WriteFile(wifiError, []byte(err.Error()+"\n"), 0o644)
		} else {
			os.Remove(wifiError)
		}
	}

	os.MkdirAll(sysMnt, 0o755)
	return nil
}

func natRules() error {
	rules := fmt.Sprintf(`table ip kazokuai
delete table ip kazokuai
table ip kazokuai {
	chain pi_postrouting {
		type nat hook postrouting priority srcnat; policy accept;
		ip saddr { 10.77.0.0/24, 10.78.0.0/24 } oifname != { "%[1]s", "%[2]s" } masquerade
	}
	chain pi_forward {
		type filter hook forward priority filter - 1; policy accept;
		iifname { "%[1]s", "%[2]s" } accept
		oifname { "%[1]s", "%[2]s" } ct state established,related accept
	}
}
`, hostIf, apIf)

	cmd := exec.Command("nft", "-f", "-")
	cmd.Stdin = strings.NewReader(rules)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("nft: %v %s", err, strings.TrimSpace(string(out)))
	}

	if _, err := exec.LookPath("iptables"); err != nil {
		return nil
	}
	for _, ifn := range []string{hostIf, apIf} {
		for _, rule := range [][]string{
			{"FORWARD", "-i", ifn, "-j", "ACCEPT"},
			{"FORWARD", "-o", ifn, "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT"},
		} {
			if exec.Command("iptables", append([]string{"-C"}, rule...)...).Run() != nil {
				exec.Command("iptables", append([]string{"-I"}, rule...)...).Run()
			}
		}
	}
	return nil
}

func kernelRelease() string {
	var u syscall.Utsname
	syscall.Uname(&u)
	var b []byte
	for _, c := range u.Release {
		if c == 0 {
			break
		}
		b = append(b, byte(c))
	}
	return string(b)
}

func loadModule(dir, name string, args ...string) error {
	if _, err := os.Stat("/sys/module/" + name); err == nil {
		return nil
	}
	if runCmd("modprobe", append([]string{name}, args...)...) == nil {
		return nil
	}
	path := dir + "/" + name + ".ko"
	if _, err := os.Stat(path); err != nil {
		return fmt.Errorf("%s がありません。sudo bash /usr/local/share/kazokuai-pisim/build-wifi-module.sh で作ってください", path)
	}
	return runCmd("insmod", append([]string{"-f", path}, args...)...)
}

func loadHwsim() error {
	dir := moduleDir + "/" + kernelRelease()
	for _, m := range []string{"libarc4", "cfg80211", "mac80211"} {
		if err := loadModule(dir, m); err != nil {
			return err
		}
	}
	for _, m := range []string{"ccm", "cmac"} {
		if err := loadModule(dir, m); err != nil {
			log.Printf("%s を読み込めませんでした(WPA2 で接続できないことがあります): %v", m, err)
		}
	}
	if err := loadModule(dir, "mac80211_hwsim", "radios=0"); err != nil {
		return fmt.Errorf("mac80211_hwsim を読み込めません: %w", err)
	}
	return nil
}

func waitFor(find func() string) string {
	for i := 0; i < 30; i++ {
		if s := find(); s != "" {
			return s
		}
		time.Sleep(100 * time.Millisecond)
	}
	return ""
}

func netnsWirelessIface() string {
	out, err := exec.Command("ip", "-n", netnsName, "-o", "link", "show").Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(line)
		if len(f) < 2 {
			continue
		}
		name := strings.TrimSuffix(strings.SplitN(f[1], "@", 2)[0], ":")
		if name != "lo" && name != "eth0" {
			return name
		}
	}
	return ""
}

func wifiUp() error {
	if err := loadHwsim(); err != nil {
		return err
	}

	for _, radio := range []string{hwsimRadioAP, hwsimRadioPi} {
		if err := hwsimRadio(radio); err != nil {
			return err
		}
	}

	ap := waitFor(func() string { return hwsimRadioIface(hwsimRadioAP) })
	if ap == "" {
		return fmt.Errorf("アクセスポイントの無線のインターフェースが見つかりません")
	}
	if ap != apIf {
		runCmd("ip", "link", "set", ap, "down")
		if err := runCmd("ip", "link", "set", ap, "name", apIf); err != nil {
			return err
		}
	}
	runCmd("ip", "addr", "flush", "dev", apIf)
	if err := runCmd("ip", "addr", "add", wifiHost+"/24", "dev", apIf); err != nil {
		return err
	}
	if err := runCmd("ip", "link", "set", apIf, "up"); err != nil {
		return err
	}

	pi := waitFor(func() string { return hwsimRadioIface(hwsimRadioPi) })
	if pi == "" {
		return fmt.Errorf("電話機の無線のインターフェースが見つかりません")
	}
	runCmd("ip", "link", "set", pi, "down")
	runCmd("ip", "link", "set", pi, "address", boardMAC(1))
	if err := runCmd("iw", "phy", hwsimRadioPi, "set", "netns", "name", netnsName); err != nil {
		return err
	}

	pi = waitFor(netnsWirelessIface)
	if pi == "" {
		return fmt.Errorf("電話機の名前空間に無線のインターフェースが見つかりません")
	}
	if pi != "wlan0" {
		if err := runCmd("ip", "-n", netnsName, "link", "set", pi, "name", "wlan0"); err != nil {
			return err
		}
	}
	return nil
}

func ifaceExists(name string) bool {
	_, err := os.Stat("/sys/class/net/" + name)
	return err == nil
}

func hostNameserver() string {
	f, err := os.Open("/etc/resolv.conf")
	if err != nil {
		return ""
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if f := strings.Fields(sc.Text()); len(f) >= 2 && f[0] == "nameserver" && !strings.Contains(f[1], ":") {
			return f[1]
		}
	}
	return ""
}

func superviseNet(cfg Config, status func(string)) {
	if !ifaceExists(hostIf) {
		status("電話機のネットワークがありません(pisim-net.service)")
		return
	}

	wifi := ifaceExists(apIf)
	if wifi {
		conf := fmt.Sprintf(`interface=%s
driver=nl80211
ssid=%s
country_code=JP
hw_mode=g
channel=6
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=%s
`, apIf, cfg.WifiSSID, cfg.WifiPassword)
		os.WriteFile(runDir+"/hostapd.conf", []byte(conf), 0o600)
		go keepRunning("hostapd", "hostapd", runDir+"/hostapd.conf")
	}

	args := []string{
		"--keep-in-foreground", "--conf-file=/dev/null", "--port=0", "--bind-interfaces",
		"--interface=" + hostIf, "--dhcp-range=10.77.0.10,10.77.0.50,255.255.255.0,12h",
		"--dhcp-leasefile=" + runDir + "/dnsmasq.leases", "--pid-file=" + runDir + "/dnsmasq.pid",
	}
	if wifi {
		args = append(args, "--interface="+apIf, "--dhcp-range=10.78.0.10,10.78.0.50,255.255.255.0,12h")
	}
	if ns := hostNameserver(); ns != "" {
		args = append(args, "--dhcp-option=option:dns-server,"+ns)
	}
	go keepRunning("dnsmasq-base", "dnsmasq", args...)

	if wifi {
		status(fmt.Sprintf("eth0 %s / wlan0 は Wi-Fi「%s」(パスワード %s)につなげます", wiredPi, cfg.WifiSSID, cfg.WifiPassword))
		return
	}
	msg := "eth0 " + wiredPi + "(無線の wlan0 はありません)"
	if b, err := os.ReadFile(wifiError); err == nil {
		msg += ": " + strings.TrimSpace(string(b))
	}
	status(msg)
}

func keepRunning(pkg, name string, args ...string) {
	for {
		path, err := exec.LookPath(name)
		if err != nil {
			log.Printf("%s がありません(apt install %s)", name, pkg)
			return
		}

		logPath := runDir + "/" + name + ".log"
		out, _ := os.Create(logPath)
		cmd := exec.Command(path, args...)
		cmd.Stdout, cmd.Stderr = out, out
		start := time.Now()
		err = cmd.Run()
		out.Close()
		log.Printf("%s が終わりました: %v(%s)", name, err, logPath)

		if time.Since(start) < 10*time.Second {
			time.Sleep(10 * time.Second)
		} else {
			time.Sleep(2 * time.Second)
		}
	}
}

func enterNetns() error {
	f, err := os.Open(netnsPath)
	if err != nil {
		return nil
	}
	defer f.Close()

	if _, _, e := syscall.RawSyscall(sysSetns, f.Fd(), syscall.CLONE_NEWNET, 0); e != 0 {
		fmt.Fprintf(os.Stderr, "pisim: 電話機のネットワークに入れません(%v)。sudo systemctl restart pisim-net で作り直せます。\n", e)
		return nil
	}

	os.MkdirAll(sysMnt, 0o755)
	if err := syscall.Mount("sysfs", sysMnt, "sysfs", syscall.MS_NOSUID|syscall.MS_NODEV|syscall.MS_NOEXEC, ""); err != nil {
		return fmt.Errorf("sysfs をマウントできません: %w", err)
	}
	defer syscall.Unmount(sysMnt, syscall.MNT_DETACH)

	for _, d := range []string{"class/net", "devices"} {
		if err := syscall.Mount(sysMnt+"/"+d, "/sys/"+d, "", syscall.MS_BIND, ""); err != nil {
			return fmt.Errorf("/sys/%s を重ねられません: %w", d, err)
		}
	}
	return nil
}
