package main

import (
	"io"
	"log"
	"math"
	"os"
	"os/exec"
	"sync"
	"time"
)

const (
	sampleRate  = 48000
	blockDur    = 10 * time.Millisecond
	blockLen    = sampleRate / 100
	renderDelay = 60 * time.Millisecond
)

type edge struct {
	t     int64
	level int8
}

type pwmState struct {
	enabled  bool
	periodNs int64
	dutyNs   int64
	inversed bool
	start    int64
}

type RingerView struct {
	Active bool    `json:"active"`
	Hz     float64 `json:"hz"`
	Duty   float64 `json:"duty"`
	Source string  `json:"source"`
}

type Audio struct {
	mu     sync.Mutex
	edges  []edge
	level  int8
	pwm    pwmState
	volume float64
	status string

	recent []edge
	view   RingerView

	onChange func()
}

func NewAudio(volume float64) *Audio {
	return &Audio{volume: volume, status: "準備中"}
}

func (a *Audio) MeasureLoop() {
	for range time.Tick(50 * time.Millisecond) {
		now := monoNow()
		a.dropStaleEdges(now)
		if a.measure(now) && a.onChange != nil {
			a.onChange()
		}
	}
}

func (a *Audio) dropStaleEdges(now int64) {
	a.mu.Lock()
	defer a.mu.Unlock()

	n := len(a.edges)
	if n == 0 || a.edges[0].t >= now-int64(2*time.Second) {
		return
	}
	k := 0
	for k < n && a.edges[k].t < now-int64(time.Second) {
		a.level = a.edges[k].level
		k++
	}
	a.edges = a.edges[k:]
}

func (a *Audio) Edge(t int64, level int) {
	a.mu.Lock()
	defer a.mu.Unlock()
	e := edge{t, int8(level)}
	a.edges = append(a.edges, e)
	a.recent = append(a.recent, e)
}

func (a *Audio) SetPWM(p pwmState) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if p.enabled && !a.pwm.enabled {
		p.start = monoNow()
	} else {
		p.start = a.pwm.start
	}
	a.pwm = p
}

func (a *Audio) SetVolume(v float64) {
	a.mu.Lock()
	a.volume = math.Max(0, math.Min(2, v))
	a.mu.Unlock()
}

func (a *Audio) setStatus(s string) {
	a.mu.Lock()
	a.status = s
	a.mu.Unlock()
}

func (a *Audio) Status() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.status
}

func (a *Audio) View() RingerView {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.view
}

func (a *Audio) measure(now int64) bool {
	const window = int64(100 * time.Millisecond)
	const maxGap = int64(5 * time.Millisecond)

	a.mu.Lock()
	defer a.mu.Unlock()

	i := 0
	for i < len(a.recent) && a.recent[i].t < now-window {
		i++
	}
	a.recent = a.recent[i:]

	old := a.view
	v := RingerView{Source: "GPIO"}

	switch {
	case a.pwm.enabled && a.pwm.periodNs > 0:
		v = RingerView{
			Active: true,
			Hz:     1e9 / float64(a.pwm.periodNs),
			Duty:   float64(a.pwm.dutyNs) / float64(a.pwm.periodNs),
			Source: "/sys/class/pwm",
		}

	case len(a.recent) >= 4:
		var rises []int64
		var high, total int64
		for j := 1; j < len(a.recent); j++ {
			d := a.recent[j].t - a.recent[j-1].t
			if d > maxGap {
				continue
			}
			total += d
			if a.recent[j-1].level == 1 {
				high += d
			}
			if a.recent[j].level == 1 {
				rises = append(rises, a.recent[j].t)
			}
		}

		var sum int64
		periods := 0
		for j := 1; j < len(rises); j++ {
			if d := rises[j] - rises[j-1]; d <= maxGap {
				sum += d
				periods++
			}
		}
		if periods > 0 && total > 0 && rises[len(rises)-1] > rises[0] {
			v.Active = true
			v.Hz = math.Round(1e9 / (float64(sum) / float64(periods)))
			v.Duty = math.Round(float64(high)/float64(total)*100) / 100
		}
	}

	a.view = v
	return old.Active != v.Active || math.Abs(old.Hz-v.Hz) > 30 || math.Abs(old.Duty-v.Duty) > 0.02
}

type biquad struct{ b0, b1, b2, a1, a2, z1, z2 float64 }

func (f *biquad) run(x float64) float64 {
	y := f.b0*x + f.z1
	f.z1 = f.b1*x - f.a1*y + f.z2
	f.z2 = f.b2*x - f.a2*y
	return y
}

func newBiquad(kind string, fc, q, gainDB float64) *biquad {
	w := 2 * math.Pi * fc / sampleRate
	cw, sw := math.Cos(w), math.Sin(w)
	alpha := sw / (2 * q)
	A := math.Pow(10, gainDB/40)

	var b0, b1, b2, a0, a1, a2 float64
	switch kind {
	case "lowpass":
		b0, b1, b2 = (1-cw)/2, 1-cw, (1-cw)/2
		a0, a1, a2 = 1+alpha, -2*cw, 1-alpha
	case "highpass":
		b0, b1, b2 = (1+cw)/2, -(1 + cw), (1+cw)/2
		a0, a1, a2 = 1+alpha, -2*cw, 1-alpha
	case "peak":
		b0, b1, b2 = 1+alpha*A, -2*cw, 1-alpha*A
		a0, a1, a2 = 1+alpha/A, -2*cw, 1-alpha/A
	}
	return &biquad{b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0}
}

type ringerCircuit struct {
	inputCap *biquad
	speaker  []*biquad
}

func newRingerCircuit() *ringerCircuit {
	return &ringerCircuit{
		inputCap: newBiquad("highpass", 20, 0.707, 0),
		speaker: []*biquad{
			newBiquad("highpass", 450, 0.9, 0),
			newBiquad("peak", 2800, 1.3, 6),
			newBiquad("lowpass", 7000, 0.7, 0),
		},
	}
}

func (c *ringerCircuit) run(highFraction float64) float64 {
	const (
		gpioVolts   = 3.3
		dividerGain = 1.0 / 11.0
		ampSupply   = 5.0
		ampGain     = 16.0
	)
	v := highFraction * gpioVolts * dividerGain
	v = c.inputCap.run(v)
	v = ampSupply * math.Tanh(v*ampGain/ampSupply)
	for _, f := range c.speaker {
		v = f.run(v)
	}
	return v / ampSupply
}

func (a *Audio) Run(out io.Writer) {
	circuit := newRingerCircuit()
	pcm := make([]byte, blockLen*2)
	dt := float64(time.Second) / sampleRate
	next := time.Now()
	t0 := float64(monoNow() - int64(renderDelay))

	for {
		a.mu.Lock()
		vol := a.volume
		pwm := a.pwm
		level := a.level
		k := 0
		for k < len(a.edges) && a.edges[k].t <= int64(t0) {
			level = a.edges[k].level
			k++
		}
		a.edges = a.edges[k:]
		a.level = level
		edges := append([]edge(nil), a.edges...)
		a.mu.Unlock()

		idx := 0
		for s := 0; s < blockLen; s++ {
			s0 := t0 + float64(s)*dt
			s1 := s0 + dt
			cur := s0
			var high float64
			for idx < len(edges) && float64(edges[idx].t) < s1 {
				et := float64(edges[idx].t)
				if level == 1 {
					high += et - cur
				}
				cur = et
				level = edges[idx].level
				idx++
			}
			if level == 1 {
				high += s1 - cur
			}

			frac := high / dt
			if pwm.enabled && pwm.periodNs > 0 {
				frac = math.Max(frac, pwmHighFraction(pwm, s0, dt))
			}

			y := math.Max(-1, math.Min(1, circuit.run(frac)*vol))
			le.PutUint16(pcm[2*s:], uint16(int16(y*32767)))
		}
		t0 += float64(blockLen) * dt

		if _, err := out.Write(pcm); err != nil {
			return
		}

		next = next.Add(blockDur)
		if d := time.Until(next); d > 0 {
			time.Sleep(d)
		} else if d < -time.Second {
			next = time.Now()
			t0 = float64(monoNow() - int64(renderDelay))
		}
	}
}

func pwmHighFraction(pwm pwmState, s0, dt float64) float64 {
	const subSamples = 8
	on := 0
	for j := 0; j < subSamples; j++ {
		t := int64(s0+dt*(float64(j)+0.5)/subSamples) - pwm.start
		if t < 0 {
			continue
		}
		high := t%pwm.periodNs < pwm.dutyNs
		if high != pwm.inversed {
			on++
		}
	}
	return float64(on) / subSamples
}

func (a *Audio) RunPulse(server, sink string) {
	for {
		cmd := exec.Command("pacat", "--playback", "--raw", "--format=s16le", "--rate=48000", "--channels=1",
			"--device="+sink, "--latency-msec=40", "--client-name=kazokuai-pisim", "--stream-name=本体スピーカー")
		cmd.Env = append(os.Environ(), "PULSE_SERVER="+server)

		stdin, err := cmd.StdinPipe()
		if err == nil {
			err = cmd.Start()
		}
		if err != nil {
			a.setStatus("本体スピーカーの音を出せません: " + err.Error())
			time.Sleep(5 * time.Second)
			a.mu.Lock()
			a.edges = nil
			a.mu.Unlock()
			continue
		}

		a.setStatus("本体スピーカー → " + sink)
		a.Run(stdin)
		stdin.Close()
		cmd.Wait()

		a.setStatus("本体スピーカーの音が止まりました。やり直します")
		log.Printf("pacat が終わりました。5 秒後にやり直します")
		time.Sleep(5 * time.Second)
	}
}

type wavWriter struct {
	f *os.File
	n uint32
}

func newWavWriter(path string) (*wavWriter, error) {
	f, err := os.Create(path)
	if err != nil {
		return nil, err
	}
	w := &wavWriter{f: f}
	w.writeHeader()
	return w, nil
}

func (w *wavWriter) writeHeader() {
	h := make([]byte, 44)
	copy(h[0:], "RIFF")
	le.PutUint32(h[4:], 36+w.n)
	copy(h[8:], "WAVEfmt ")
	le.PutUint32(h[16:], 16)
	le.PutUint16(h[20:], 1)
	le.PutUint16(h[22:], 1)
	le.PutUint32(h[24:], sampleRate)
	le.PutUint32(h[28:], sampleRate*2)
	le.PutUint16(h[32:], 2)
	le.PutUint16(h[34:], 16)
	copy(h[36:], "data")
	le.PutUint32(h[40:], w.n)
	w.f.WriteAt(h, 0)
}

func (w *wavWriter) Write(p []byte) (int, error) {
	n, err := w.f.WriteAt(p, 44+int64(w.n))
	w.n += uint32(n)
	w.writeHeader()
	return n, err
}
