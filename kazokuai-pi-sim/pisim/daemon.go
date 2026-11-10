package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"
)

func runDaemon(args []string) error {
	fs := flag.NewFlagSet("daemon", flag.ContinueOnError)
	confPath := fs.String("config", configPath, "配線の設定ファイル")
	audioFile := fs.String("audio-file", "", "本体スピーカーの音を PulseAudio ではなくこの WAV ファイルに書く(試験用)")
	noPulse := fs.Bool("no-pulse", false, "PulseAudio に受話器と本体スピーカーを作らない")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if os.Geteuid() != 0 {
		return errors.New("pisim daemon は root で動かしてください")
	}

	cfg, err := LoadConfig(*confPath)
	if err != nil {
		return err
	}
	log.Printf("配線: %s", cfg.Summary())

	if err := os.MkdirAll(runDir, 0o755); err != nil {
		return err
	}
	if err := prepareSysfs(); err != nil {
		return err
	}
	defer cleanupSysfs()
	ensureHostsEntry()

	audio := NewAudio(cfg.Volume)
	board := NewBoard(cfg, audio)
	audio.onChange = board.notify
	go audio.MeasureLoop()

	pulse := &Pulse{server: cfg.PulseServer, name: cfg.AudioName}
	switch {
	case *audioFile != "":
		w, err := newWavWriter(*audioFile)
		if err != nil {
			return err
		}
		audio.setStatus("本体スピーカー → " + *audioFile)
		go audio.Run(w)
	case *noPulse:
		audio.setStatus("本体スピーカーの音は出しません(--no-pulse)")
		go audio.Run(io.Discard)
	default:
		go superviseAudio(pulse, audio, board, cfg.PulseServer)
		defer pulse.Teardown()
	}

	network := &netStatus{}
	superviseNet(cfg, network.set)

	pwm := &PWM{audio: audio, ringer: cfg.RingerGPIO}
	if err := pwm.setup(); err != nil {
		log.Printf("/sys/class/pwm を用意できませんでした: %v", err)
	} else {
		go pwm.Run()
	}

	gpio := &Gpio{board: board}
	store := newFDStore()
	for fd, name := range inheritedFDs() {
		if !strings.HasPrefix(name, "gpio-") {
			syscall.Close(fd)
			continue
		}
		go func(fd int, name string) {
			gpio.Serve(fd)
			store.Drop(name)
		}(fd, name)
	}

	enroll, err := listenUnix(enrollSock, 0o600)
	if err != nil {
		return err
	}
	defer os.Remove(enrollSock)
	go acceptEnroll(enroll, gpio, store)

	gui, err := listenUnix(guiSock, 0o666)
	if err != nil {
		return err
	}
	defer os.Remove(guiSock)
	hub := &guiHub{board: board, pulse: pulse, audio: audio, network: network}
	go hub.serve(gui)
	go hub.broadcastLoop()

	go func() {
		for range time.Tick(500 * time.Millisecond) {
			board.mu.Lock()
			board.reapLocked()
			board.mu.Unlock()
		}
	}()

	log.Printf("電話機のラズパイを動かしました。%s を作りました", chipPath)
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	log.Printf("止めます")
	return nil
}

func superviseAudio(pulse *Pulse, audio *Audio, board *Board, server string) {
	for i := 0; ; i++ {
		err := pulse.Setup()
		if err == nil {
			break
		}
		if i == 0 {
			log.Printf("音声の機器をまだ作れません。つながるまで待ちます: %v", err)
		}
		audio.setStatus("WSLg の PulseAudio につながるのを待っています")
		time.Sleep(5 * time.Second)
	}
	log.Printf("音声: %s", pulse.Status())

	pulse.SetHandsetMuted(!board.HookLifted())
	board.mu.Lock()
	board.onHook = func(lifted bool) { pulse.SetHandsetMuted(!lifted) }
	board.mu.Unlock()

	go audio.RunPulse(server, bodySink)

	for range time.Tick(10 * time.Second) {
		if pulse.Exists() {
			continue
		}
		log.Printf("PulseAudio の受話器と本体スピーカーが消えていたので、作り直します")
		pulse.mu.Lock()
		pulse.modules = nil
		pulse.mu.Unlock()
		if err := pulse.Setup(); err != nil {
			log.Printf("作り直せませんでした: %v", err)
			continue
		}
		pulse.SetHandsetMuted(!board.HookLifted())
	}
}

type netStatus struct {
	mu sync.Mutex
	s  string
}

func (n *netStatus) set(s string) {
	n.mu.Lock()
	n.s = s
	n.mu.Unlock()
	log.Printf("ネットワーク: %s", s)
}

func (n *netStatus) get() string {
	n.mu.Lock()
	defer n.mu.Unlock()
	return n.s
}

func listenUnix(path string, mode os.FileMode) (*net.UnixListener, error) {
	os.Remove(path)
	l, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		return nil, err
	}
	os.Chmod(path, mode)
	return l, nil
}

func acceptEnroll(l *net.UnixListener, gpio *Gpio, store *fdStore) {
	for {
		c, err := l.AcceptUnix()
		if err != nil {
			return
		}
		go func() {
			defer c.Close()
			fd, ok := receiveFD(c)
			if !ok {
				return
			}
			c.Write([]byte("ok"))
			name := store.Keep(fd)
			gpio.Serve(fd)
			store.Drop(name)
		}()
	}
}

func receiveFD(c *net.UnixConn) (int, bool) {
	buf := make([]byte, 64)
	oob := make([]byte, syscall.CmsgSpace(4))
	_, oobn, _, _, err := c.ReadMsgUnix(buf, oob)
	if err != nil {
		return -1, false
	}
	msgs, err := syscall.ParseSocketControlMessage(oob[:oobn])
	if err != nil || len(msgs) == 0 {
		return -1, false
	}
	fds, err := syscall.ParseUnixRights(&msgs[0])
	if err != nil || len(fds) != 1 {
		return -1, false
	}
	return fds[0], true
}

type guiHub struct {
	board   *Board
	pulse   *Pulse
	audio   *Audio
	network *netStatus
	mu      sync.Mutex
	conns   map[*net.UnixConn]chan []byte
}

func (h *guiHub) snapshot() []byte {
	s := h.board.Snapshot()
	if st := h.pulse.Status(); st != "" {
		s.Audio = st + " ・ " + s.Audio
	}
	s.Network = h.network.get()
	b, _ := json.Marshal(s)
	return append(b, '\n')
}

func (h *guiHub) serve(l *net.UnixListener) {
	for {
		c, err := l.AcceptUnix()
		if err != nil {
			return
		}

		out := make(chan []byte, 16)
		h.mu.Lock()
		if h.conns == nil {
			h.conns = map[*net.UnixConn]chan []byte{}
		}
		h.conns[c] = out
		h.mu.Unlock()
		out <- h.snapshot()

		go func() {
			for msg := range out {
				if _, err := c.Write(msg); err != nil {
					c.Close()
					return
				}
			}
		}()
		go h.read(c, out)
	}
}

type guiMessage struct {
	T    string  `json:"t"`
	Up   bool    `json:"up"`
	K    string  `json:"k"`
	Down bool    `json:"down"`
	V    float64 `json:"v"`
}

func (h *guiHub) read(c *net.UnixConn, out chan []byte) {
	defer func() {
		h.mu.Lock()
		delete(h.conns, c)
		h.mu.Unlock()
		close(out)
		c.Close()
	}()

	sc := bufio.NewScanner(c)
	for sc.Scan() {
		var m guiMessage
		if json.Unmarshal(sc.Bytes(), &m) != nil {
			continue
		}
		switch m.T {
		case "hook":
			h.board.SetHook(m.Up)
		case "key":
			if len(m.K) == 1 {
				h.board.SetKey(m.K[0], m.Down)
			}
		case "volume":
			h.audio.SetVolume(m.V)
		case "release-keys":
			for _, k := range []byte("0123456789*#") {
				h.board.SetKey(k, false)
			}
		}
	}
}

func (h *guiHub) broadcastLoop() {
	tick := time.NewTicker(time.Second)
	for {
		select {
		case <-h.board.changed:
		case <-tick.C:
		}

		msg := h.snapshot()
		h.mu.Lock()
		for _, out := range h.conns {
			select {
			case out <- msg:
			default:
			}
		}
		h.mu.Unlock()
		time.Sleep(33 * time.Millisecond)
	}
}

func printStatus() error {
	c, err := net.Dial("unix", guiSock)
	if err != nil {
		return fmt.Errorf("電話機のラズパイ(pisim daemon)が動いていません: %w", err)
	}
	defer c.Close()

	line, err := bufio.NewReader(c).ReadBytes('\n')
	if err != nil {
		return err
	}
	var s StateView
	if err := json.Unmarshal(line, &s); err != nil {
		return err
	}

	hook := "置いてある"
	if s.HookUp {
		hook = "上がっている"
	}
	fmt.Printf("受話器: %s / 押しているキー: %q / 電話機のシェル: %d\n", hook, s.Keys, s.Sessions)
	fmt.Printf("配線: %s\n", s.Config)
	for _, l := range s.Lines {
		fmt.Printf("  %s %s %s 値=%d プル=%s %s\n",
			padRight(fmt.Sprintf("GPIO%d", l.GPIO), 6), padRight(l.Role, 14), l.Dir, l.Level, padRight(l.Pull, 4), l.Owner)
	}
	if s.Ringer.Active {
		fmt.Printf("本体スピーカー: %.0f Hz デューティ %.0f%% (%s)\n", s.Ringer.Hz, s.Ringer.Duty*100, s.Ringer.Source)
	}
	fmt.Printf("音: %s\n", s.Audio)
	fmt.Printf("ネットワーク: %s\n", s.Network)
	return nil
}

func padRight(s string, width int) string {
	if w := displayWidth(s); w < width {
		return s + strings.Repeat(" ", width-w)
	}
	return s
}

func displayWidth(s string) int {
	w := 0
	for _, r := range s {
		if isWide(r) {
			w += 2
		} else if r >= 0x20 && r != utf8.RuneError {
			w++
		}
	}
	return w
}

func isWide(r rune) bool {
	return r >= 0x1100 && (r <= 0x115f ||
		(r >= 0x2e80 && r <= 0xa4cf && r != 0x303f) ||
		(r >= 0xac00 && r <= 0xd7a3) ||
		(r >= 0xf900 && r <= 0xfaff) ||
		(r >= 0xfe30 && r <= 0xfe4f) ||
		(r >= 0xff00 && r <= 0xff60) ||
		(r >= 0xffe0 && r <= 0xffe6) ||
		(r >= 0x20000 && r <= 0x3fffd))
}
