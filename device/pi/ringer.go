package pi

import (
	"fmt"
	"io"
	"sync"
	"time"

	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/internal/clock"
)

const (
	ringerLowHz  = 1200
	ringerHighHz = 1600
	// ringerDuty は、周期を何等分した時間だけ入れるかである。10 なら 10%。
	ringerDuty = 10
	// ringerPairs は、1,200 Hz と 1,600 Hz の対を何回鳴らすと 1 秒になるかである。
	ringerPairs = 16
	ringerSlice = time.Second / 32
	ringerPause = 2 * time.Second
)

// Pin は、呼び出し音が駆動する GPIO である。1 で入れ、0 で切る。
type Pin interface {
	Set(level int) error
	Close() error
}

// Ringer は、GPIO をゴルーチンで入れたり切ったりして、本体のスピーカーを鳴らす。
// 1,200 Hz と 1,600 Hz を 1/32 秒ずつ 1 秒鳴らし、2 秒止める。入れている時間は周期の 10% である。
// CPU が忙しいと周期は少しぶれる。
type Ringer struct {
	pin   Pin
	clock clock.Clock
	out   io.Writer

	mu     sync.Mutex
	stop   chan struct{}
	done   chan struct{}
	closed bool
}

func newRinger(pin Pin, clk clock.Clock, out io.Writer) *Ringer {
	if clk == nil {
		clk = clock.Real{}
	}
	if out == nil {
		out = io.Discard
	}
	return &Ringer{pin: pin, clock: clk, out: out}
}

// Ring は呼び出し音を鳴らす。すでに鳴っていれば、何もしない。
func (r *Ringer) Ring() {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.closed || r.done != nil {
		return
	}
	stop := make(chan struct{})
	done := make(chan struct{})
	r.stop = stop
	r.done = done
	fmt.Fprintln(r.out, "呼び出し中です。")
	go r.run(stop, done)
}

// Stop は、周期の途中でもすぐ線を切る。鳴っていなければ、切ったままにする。
func (r *Ringer) Stop() {
	r.mu.Lock()
	stop := r.stop
	done := r.done
	r.stop = nil
	r.done = nil
	r.mu.Unlock()
	if done != nil {
		close(stop)
		<-done
		fmt.Fprintln(r.out, "呼び出しが止まりました。")
	}
	r.silence()
}

// Close は鳴るのをやめ、GPIO を放す。
func (r *Ringer) Close() error {
	r.mu.Lock()
	if r.closed {
		r.mu.Unlock()
		return nil
	}
	r.closed = true
	r.mu.Unlock()
	r.Stop()
	if r.pin == nil {
		return nil
	}
	return r.pin.Close()
}

func (r *Ringer) run(stop <-chan struct{}, done chan struct{}) {
	defer close(done)
	defer r.silence()
	for {
		if !r.burst(stop) {
			return
		}
		r.silence()
		if !r.wait(stop, ringerPause) {
			return
		}
	}
}

func (r *Ringer) burst(stop <-chan struct{}) bool {
	for i := 0; i < ringerPairs; i++ {
		for _, hz := range []int{ringerLowHz, ringerHighHz} {
			if !r.tone(stop, hz, ringerSlice) {
				return false
			}
		}
	}
	return true
}

// tone は、hz の音を length のあいだ出す。1/32 秒で次の高さへ移すので、最後の切れは短くなる。
func (r *Ringer) tone(stop <-chan struct{}, hz int, length time.Duration) bool {
	period := time.Second / time.Duration(hz)
	on := period / ringerDuty
	off := period - on
	end := r.clock.Now().Add(length)
	for {
		if !r.clock.Now().Before(end) {
			return true
		}
		high := on
		if remain := end.Sub(r.clock.Now()); high > remain {
			high = remain
		}
		if !r.drive(1) || !r.wait(stop, high) {
			return false
		}
		if !r.clock.Now().Before(end) {
			return r.drive(0)
		}
		low := off
		if remain := end.Sub(r.clock.Now()); low > remain {
			low = remain
		}
		if !r.drive(0) || !r.wait(stop, low) {
			return false
		}
	}
}

func (r *Ringer) wait(stop <-chan struct{}, d time.Duration) bool {
	timer := r.clock.NewTimer(d)
	defer timer.Stop()
	select {
	case <-stop:
		return false
	case <-timer.Chan():
		return true
	}
}

func (r *Ringer) drive(level int) bool {
	if err := r.pin.Set(level); err != nil {
		fmt.Fprintf(r.out, "呼び出し音を出せなかった: %v\n", err)
		return false
	}
	return true
}

func (r *Ringer) silence() {
	if r.pin == nil {
		return
	}
	if err := r.pin.Set(0); err != nil {
		fmt.Fprintf(r.out, "呼び出し音を切れなかった: %v\n", err)
	}
}

var _ phone.Ringer = (*Ringer)(nil)
