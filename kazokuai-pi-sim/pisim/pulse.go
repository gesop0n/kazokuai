package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"sync"
)

const (
	handsetSink   = "kazokuai_handset"
	handsetSource = "kazokuai_handset_mic"
	bodySink      = "kazokuai_body"
)

type Pulse struct {
	server  string
	name    string
	mu      sync.Mutex
	modules []string
	status  string
}

func (p *Pulse) pactl(args ...string) (string, error) {
	cmd := exec.Command("pactl", args...)
	cmd.Env = append(os.Environ(), "PULSE_SERVER="+p.server, "LANG=C")
	out, err := cmd.CombinedOutput()
	s := strings.TrimSpace(string(out))
	if err != nil {
		return s, fmt.Errorf("pactl %s: %v %s", strings.Join(args, " "), err, s)
	}
	return s, nil
}

func (p *Pulse) load(args ...string) error {
	idx, err := p.pactl(append([]string{"load-module"}, args...)...)
	if err != nil {
		return err
	}
	p.modules = append(p.modules, idx)
	return nil
}

func description(kind, name string) string {
	return fmt.Sprintf(`%s_properties="device.description='%s'"`, kind, name)
}

func (p *Pulse) unloadLeftovers() {
	list, err := p.pactl("list", "short", "modules")
	if err != nil {
		return
	}
	for _, line := range strings.Split(list, "\n") {
		if !strings.Contains(line, "kazokuai_") {
			continue
		}
		if f := strings.Fields(line); len(f) > 0 {
			p.pactl("unload-module", f[0])
		}
	}
}

func (p *Pulse) Setup() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if _, err := p.pactl("info"); err != nil {
		p.status = "PulseAudio(WSLg)につながりません"
		return err
	}
	p.unloadLeftovers()

	sink, _ := p.pactl("get-default-sink")
	if sink == "" {
		sink = "RDPSink"
	}
	source, _ := p.pactl("get-default-source")
	if source == "" {
		source = "RDPSource"
	}

	err := p.load("module-echo-cancel", "aec_method=webrtc", "rate=48000", "channels=1",
		"source_master="+source, "sink_master="+sink,
		"source_name="+handsetSource, "sink_name="+handsetSink,
		description("source", p.name), description("sink", p.name))
	echoCancel := err == nil
	if !echoCancel {
		log.Printf("エコーキャンセルを使えないので、そのままつなぎます: %v", err)
		if err := p.load("module-remap-sink", "sink_name="+handsetSink, "master="+sink,
			"channels=1", "channel_map=mono", description("sink", p.name)); err != nil {
			p.status = "受話器のスピーカーを作れません"
			return err
		}
		if err := p.load("module-remap-source", "source_name="+handsetSource, "master="+source,
			"channels=1", "channel_map=mono", description("source", p.name)); err != nil {
			p.status = "受話器のマイクを作れません"
			return err
		}
	}

	if err := p.load("module-remap-sink", "sink_name="+bodySink, "master="+sink,
		"channels=1", "channel_map=mono", description("sink", "本体スピーカー (PAM8012)")); err != nil {
		p.status = "本体スピーカーを作れません"
		return err
	}

	p.status = fmt.Sprintf("受話器「%s」→ %s / %s", p.name, sink, source)
	if echoCancel {
		p.status += "(エコーキャンセルあり)"
	}
	return nil
}

func (p *Pulse) Exists() bool {
	sinks, err := p.pactl("list", "short", "sinks")
	if err != nil {
		return false
	}
	sources, err := p.pactl("list", "short", "sources")
	if err != nil {
		return false
	}

	has := func(list, name string) bool {
		for _, line := range strings.Split(list, "\n") {
			if f := strings.Fields(line); len(f) >= 2 && f[1] == name {
				return true
			}
		}
		return false
	}
	return has(sinks, handsetSink) && has(sinks, bodySink) && has(sources, handsetSource)
}

func (p *Pulse) SetHandsetMuted(muted bool) {
	v := "0"
	if muted {
		v = "1"
	}
	go func() {
		p.pactl("set-sink-mute", handsetSink, v)
		p.pactl("set-source-mute", handsetSource, v)
	}()
}

func (p *Pulse) Status() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.status
}

func (p *Pulse) Teardown() {
	p.mu.Lock()
	defer p.mu.Unlock()
	for i := len(p.modules) - 1; i >= 0; i-- {
		p.pactl("unload-module", p.modules[i])
	}
	p.modules = nil
}
