package main

import (
	"bytes"
	"crypto/sha256"
	"fmt"
	"log"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"unsafe"
)

const (
	runDir      = "/run/pisim"
	sysDir      = runDir + "/sys"
	busGpioDir  = sysDir + "/bus_gpio"
	devCharDir  = sysDir + "/dev_char"
	classPwmDir = sysDir + "/class_pwm"
	cpuinfoPath = runDir + "/cpuinfo"
	enrollSock  = runDir + "/enroll.sock"
	guiSock     = runDir + "/gui.sock"

	chipMajor = 1
	chipMinor = 7

	piRevision = "c03114"
	piModel    = "Raspberry Pi 4 Model B Rev 1.4"
)

type bindMount struct{ source, target string }

var bindMounts = []bindMount{
	{busGpioDir, "/sys/bus/gpio"},
	{devCharDir, "/sys/dev/char"},
	{classPwmDir, "/sys/class/pwm"},
	{cpuinfoPath, "/proc/cpuinfo"},
}

func boardID() [32]byte {
	id, err := os.ReadFile("/etc/machine-id")
	if err != nil || len(bytes.TrimSpace(id)) == 0 {
		id = []byte("kazokuai")
	}
	return sha256.Sum256(bytes.TrimSpace(id))
}

func boardSerial() string {
	h := boardID()
	return fmt.Sprintf("10000000%02x%02x%02x%02x", h[0], h[1], h[2], h[3])
}

func boardMAC(offset int) string {
	h := boardID()
	n := (int(h[4])<<16 | int(h[5])<<8 | int(h[6])) + offset
	return fmt.Sprintf("dc:a6:32:%02x:%02x:%02x", n>>16&0xff, n>>8&0xff, n&0xff)
}

func gpioGroup() (int, bool) {
	g, err := user.LookupGroup("gpio")
	if err != nil {
		return 0, false
	}
	gid, err := strconv.Atoi(g.Gid)
	return gid, err == nil
}

func writeReadOnly(path, content string) {
	os.Remove(path)
	os.WriteFile(path, []byte(content), 0o444)
}

func prepareSysfs() error {
	chipDir := busGpioDir + "/devices/gpiochip0"
	for _, d := range []string{chipDir, busGpioDir + "/drivers", devCharDir, classPwmDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return err
		}
	}

	dev := fmt.Sprintf("%d:%d", chipMajor, chipMinor)
	uevent := fmt.Sprintf("MAJOR=%d\nMINOR=%d\nDEVNAME=gpiochip0\nOF_NAME=gpio\n", chipMajor, chipMinor)

	writeReadOnly(chipDir+"/dev", dev+"\n")
	writeReadOnly(chipDir+"/uevent", uevent)
	os.Remove(chipDir + "/subsystem")
	os.Symlink("/sys/bus/gpio", chipDir+"/subsystem")
	writeReadOnly(busGpioDir+"/drivers_autoprobe", "1\n")

	if old, err := os.ReadDir(devCharDir); err == nil {
		for _, e := range old {
			os.RemoveAll(filepath.Join(devCharDir, e.Name()))
		}
	}
	if ents, err := os.ReadDir("/sys/dev/char"); err == nil {
		for _, e := range ents {
			if t, err := os.Readlink(filepath.Join("/sys/dev/char", e.Name())); err == nil {
				os.Symlink(t, filepath.Join(devCharDir, e.Name()))
			}
		}
	}
	chipChar := filepath.Join(devCharDir, dev)
	os.RemoveAll(chipChar)
	os.MkdirAll(chipChar, 0o755)
	writeReadOnly(chipChar+"/dev", dev+"\n")
	writeReadOnly(chipChar+"/uevent", uevent)
	os.Symlink("/sys/bus/gpio", chipChar+"/subsystem")

	if err := writeCpuinfo(); err != nil {
		return err
	}

	os.Remove(chipPath)
	if err := syscall.Mknod(chipPath, syscall.S_IFCHR|0o660, chipMajor<<8|chipMinor); err != nil {
		return fmt.Errorf("%s を作れませんでした: %w", chipPath, err)
	}
	os.Chmod(chipPath, 0o660)
	if gid, ok := gpioGroup(); ok {
		os.Chown(chipPath, 0, gid)
	}
	return nil
}

func writeCpuinfo() error {
	base, _ := os.ReadFile("/proc/cpuinfo")
	pi := fmt.Sprintf("Revision\t: %s\nSerial\t\t: %s\nModel\t\t: %s\n", piRevision, boardSerial(), piModel)
	content := strings.TrimRight(string(base), "\n") + "\n\n" + pi
	return os.WriteFile(cpuinfoPath, []byte(content), 0o444)
}

func cleanupSysfs() {
	os.Remove(chipPath)
}

func ensureHostsEntry() {
	b, err := os.ReadFile("/etc/hosts")
	if err != nil {
		return
	}
	for _, line := range strings.Split(string(b), "\n") {
		f := strings.Fields(line)
		for _, name := range f[min(1, len(f)):] {
			if name == piHostname {
				return
			}
		}
	}
	entry := "127.0.1.1\t" + piHostname + "\n"
	if len(b) > 0 && b[len(b)-1] != '\n' {
		entry = "\n" + entry
	}
	f, err := os.OpenFile("/etc/hosts", os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		return
	}
	defer f.Close()
	f.WriteString(entry)
}

var pwmChannelGPIO = []int{18, 19}

type PWM struct {
	audio  *Audio
	ringer int
	fd     int
	watch  map[int]string
}

func (p *PWM) chipDir() string { return classPwmDir + "/pwmchip0" }

func (p *PWM) setup() error {
	d := p.chipDir()
	if err := os.MkdirAll(d, 0o755); err != nil {
		return err
	}

	gid, hasGroup := gpioGroup()
	create := func(name, val string, mode os.FileMode) {
		path := filepath.Join(d, name)
		os.WriteFile(path, []byte(val), mode)
		os.Chmod(path, mode)
		if hasGroup {
			os.Chown(path, 0, gid)
		}
	}
	create("npwm", fmt.Sprintf("%d\n", len(pwmChannelGPIO)), 0o444)
	create("export", "", 0o222)
	create("unexport", "", 0o222)

	fd, err := syscall.InotifyInit1(syscall.IN_CLOEXEC)
	if err != nil {
		return err
	}
	p.fd = fd
	p.watch = map[int]string{}
	return p.addWatch(d)
}

func (p *PWM) addWatch(dir string) error {
	wd, err := syscall.InotifyAddWatch(p.fd, dir, syscall.IN_CLOSE_WRITE)
	if err != nil {
		return err
	}
	p.watch[wd] = dir
	return nil
}

func (p *PWM) Run() {
	buf := make([]byte, 4096)
	for {
		n, err := syscall.Read(p.fd, buf)
		if err == syscall.EINTR {
			continue
		}
		if err != nil {
			log.Printf("/sys/class/pwm の見張りが止まりました: %v", err)
			return
		}

		for off := 0; off+syscall.SizeofInotifyEvent <= n; {
			ev := (*syscall.InotifyEvent)(unsafe.Pointer(&buf[off]))
			nameStart := off + syscall.SizeofInotifyEvent
			name := ""
			if ev.Len > 0 {
				name = cstr(buf[nameStart : nameStart+int(ev.Len)])
			}
			off = nameStart + int(ev.Len)
			p.changed(p.watch[int(ev.Wd)], name)
		}
	}
}

func readTrim(path string) string {
	b, _ := os.ReadFile(path)
	return strings.TrimSpace(string(b))
}

func (p *PWM) changed(dir, name string) {
	chip := p.chipDir()

	if dir == chip {
		path := filepath.Join(chip, name)
		val := readTrim(path)
		os.WriteFile(path, nil, 0)

		ch, err := strconv.Atoi(val)
		if err != nil || ch < 0 || ch >= len(pwmChannelGPIO) {
			return
		}
		channelDir := filepath.Join(chip, fmt.Sprintf("pwm%d", ch))
		switch name {
		case "export":
			p.export(channelDir)
		case "unexport":
			os.RemoveAll(channelDir)
			p.apply(ch, channelDir)
		}
		return
	}

	if base := filepath.Base(dir); strings.HasPrefix(base, "pwm") {
		ch, _ := strconv.Atoi(strings.TrimPrefix(base, "pwm"))
		p.apply(ch, dir)
	}
}

func (p *PWM) export(channelDir string) {
	if _, err := os.Stat(channelDir); err == nil {
		return
	}

	gid, hasGroup := gpioGroup()
	os.MkdirAll(channelDir, 0o775)
	if hasGroup {
		os.Chown(channelDir, 0, gid)
	}
	for name, val := range map[string]string{"period": "0", "duty_cycle": "0", "enable": "0", "polarity": "normal"} {
		path := filepath.Join(channelDir, name)
		os.WriteFile(path, []byte(val+"\n"), 0o664)
		os.Chmod(path, 0o666)
		if hasGroup {
			os.Chown(path, 0, gid)
		}
	}
	p.addWatch(channelDir)
}

func (p *PWM) apply(ch int, channelDir string) {
	if ch >= len(pwmChannelGPIO) || pwmChannelGPIO[ch] != p.ringer {
		return
	}

	period, _ := strconv.ParseInt(readTrim(filepath.Join(channelDir, "period")), 10, 64)
	duty, _ := strconv.ParseInt(readTrim(filepath.Join(channelDir, "duty_cycle")), 10, 64)
	enabled := readTrim(filepath.Join(channelDir, "enable")) == "1"
	inversed := readTrim(filepath.Join(channelDir, "polarity")) == "inversed"
	duty = min(duty, period)

	p.audio.SetPWM(pwmState{enabled: enabled && period > 0, periodNs: period, dutyNs: duty, inversed: inversed})
}
