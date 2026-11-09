package pi

import (
	"bytes"
	"fmt"
	"io"
	"runtime"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/gesop0n/kazokuai/internal/clock"
)

// 1200 Hz の周期は 833333ns で、その 10% は 83333ns。1/32 秒は 31250000ns なので、
// 37 回のあと最後の切れだけ 333346ns になる。1600 Hz は周期 625000ns がちょうど 50 回入る。
const (
	pulseOn1200   = 83333 * time.Nanosecond
	pulseOff1200  = 750000 * time.Nanosecond
	pulseTail1200 = 333346 * time.Nanosecond
	pulseOn1600   = 62500 * time.Nanosecond
	pulseOff1600  = 562500 * time.Nanosecond
)

func TestRingerAlternatesTheTonesForASecondThenPausesAndRepeats(t *testing.T) {
	pin := &fakePin{}
	clk := newStepClock()
	ringer := newRinger(pin, clk, io.Discard)
	ringer.Ring()
	defer ringer.Stop()

	steps := recordRing(t, clk, pin, time.Second+2*time.Second+time.Second/32)
	if err := warble(steps); err != nil {
		t.Fatal(err)
	}
}

func TestStopSilencesTheRingerBeforeThePulseFinishes(t *testing.T) {
	pin := &fakePin{}
	clk := newStepClock()
	var out bytes.Buffer
	ringer := newRinger(pin, clk, &out)
	ringer.Ring()
	clk.waitArmed(t)
	if pin.Level() != 1 {
		t.Fatalf("鳴り始め = %d, want 1", pin.Level())
	}
	if got := clk.pendingFor(); got != pulseOn1200 {
		t.Fatalf("最初の入り = %s, want %s", got, pulseOn1200)
	}
	before := clk.Now()
	ringer.Stop()
	if pin.Level() != 0 {
		t.Fatalf("止めた直後 = %d, want 0", pin.Level())
	}
	if clk.Now() != before {
		t.Fatal("止めるのに時計を進めた")
	}
	clk.Advance(time.Second)
	if pin.Level() != 0 || clk.hasPending() {
		t.Fatal("止めたあとにまた鳴った")
	}
	if out.String() != "呼び出し中です。\n呼び出しが止まりました。\n" {
		t.Fatalf("ログ =\n%s", out.String())
	}
}

func TestStopDuringThePauseDoesNotWaitOutTheSilence(t *testing.T) {
	pin := &fakePin{}
	clk := newStepClock()
	ringer := newRinger(pin, clk, io.Discard)
	ringer.Ring()
	recordRing(t, clk, pin, time.Second)
	clk.waitArmed(t)
	if pin.Level() != 0 {
		t.Fatal("休みなのに鳴っている")
	}
	if got := clk.pendingFor(); got != 2*time.Second {
		t.Fatalf("休み = %s, want 2s", got)
	}
	before := clk.Now()
	ringer.Stop()
	if clk.Now() != before {
		t.Fatal("止めるのに 2 秒の休みを進めた")
	}
	if pin.Level() != 0 {
		t.Fatal("止めたあとも鳴っている")
	}
	clk.Advance(2 * time.Second)
	if pin.Level() != 0 || clk.hasPending() {
		t.Fatal("止めたあとにまた鳴った")
	}
}

func TestRingerRingsAgainAfterItHasStopped(t *testing.T) {
	pin := &fakePin{}
	clk := newStepClock()
	ringer := newRinger(pin, clk, io.Discard)
	ringer.Ring()
	clk.waitArmed(t)
	ringer.Stop()
	ringer.Ring()
	defer ringer.Stop()
	clk.waitArmed(t)
	if pin.Level() != 1 {
		t.Fatalf("もう一度 = %d, want 1", pin.Level())
	}
	if got := clk.pendingFor(); got != pulseOn1200 {
		t.Fatalf("もう一度の入り = %s, want %s", got, pulseOn1200)
	}
}

func TestRingerHoldsThePitchAndDutyOnTheRealClock(t *testing.T) {
	// 中央値を見るので、忙しいマシンで一拍だけ遅れても失敗しない。
	// 幅は指定の 0.7–1.3 倍と、デューティー比 4–25% である。
	// タイマー待ちの実測（260 Hz 前後、約 50%）はこの幅の外にある。
	// mise run check は -short を付けない。-short のときだけ、この実時計の測定を飛ばす。
	if testing.Short() {
		t.Skip("実時計の音程は -short では測らない")
	}
	t.Run("1200", func(t *testing.T) {
		pin := &timedPin{}
		ringer := newRinger(pin, clock.Real{}, io.Discard)
		ringer.Ring()
		waitForCycles(t, pin, 12)
		started := time.Now()
		ringer.Stop()
		if elapsed := time.Since(started); elapsed > 20*time.Millisecond {
			t.Fatalf("止めるのに %s かかった", elapsed)
		}
		if pin.Level() != 0 {
			t.Fatal("止めたあとも鳴っている")
		}
		periods, duties := cycleStats(pin.snapshot(), 12)
		assertPitch(t, 1200, periods, duties)
	})
	t.Run("1600", func(t *testing.T) {
		pin := &timedPin{}
		ringer := newRinger(pin, clock.Real{}, io.Discard)
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()
		if !ringer.tone(make(chan struct{}), ringerHighHz, 15*time.Millisecond) {
			t.Fatal("1,600 Hz が途中で止まった")
		}
		periods, duties := cycleStats(pin.snapshot(), 12)
		assertPitch(t, 1600, periods, duties)
	})
}

func TestPauseWaitsOnTheClockSoStopEndsIt(t *testing.T) {
	ringer := newRinger(&fakePin{}, clock.Real{}, io.Discard)
	stop := make(chan struct{})
	done := make(chan bool, 1)
	go func() {
		done <- ringer.wait(stop, ringerPause)
	}()
	time.Sleep(20 * time.Millisecond)
	close(stop)
	select {
	case cont := <-done:
		if cont {
			t.Fatal("止めたのに休みが終わった")
		}
	case <-time.After(200 * time.Millisecond):
		t.Fatal("休みをすぐ止められなかった")
	}
}

func waitForCycles(t *testing.T, pin *timedPin, n int) {
	t.Helper()
	deadline := time.Now().Add(200 * time.Millisecond)
	for pin.cycles() < n {
		if time.Now().After(deadline) {
			t.Fatalf("周期が %d しかなかった", pin.cycles())
		}
		time.Sleep(time.Millisecond)
	}
}

func assertPitch(t *testing.T, hz int, periods []time.Duration, duties []float64) {
	t.Helper()
	if len(periods) < 8 {
		t.Fatalf("%d Hz の周期が %d しかなかった", hz, len(periods))
	}
	freq := float64(time.Second) / float64(medianDuration(periods))
	duty := medianFloat(duties)
	lo, hi := float64(hz)*0.7, float64(hz)*1.3
	if freq < lo || freq > hi {
		t.Fatalf("%d Hz の実測 = %.0f Hz, 許容 %.0f–%.0f。デューティー比 = %.1f%%", hz, freq, lo, hi, duty*100)
	}
	if duty < 0.04 || duty > 0.25 {
		t.Fatalf("%d Hz のデューティー比 = %.1f%%, 許容 4–25%%。実測 = %.0f Hz", hz, duty*100, freq)
	}
}

func cycleStats(edges []pinEdge, limit int) ([]time.Duration, []float64) {
	var periods []time.Duration
	var duties []float64
	for i := 0; i+2 < len(edges) && len(periods) < limit; i += 2 {
		if edges[i].level != 1 || edges[i+1].level != 0 || edges[i+2].level != 1 {
			continue
		}
		high := edges[i+1].at.Sub(edges[i].at)
		low := edges[i+2].at.Sub(edges[i+1].at)
		period := high + low
		if period <= 0 {
			continue
		}
		periods = append(periods, period)
		duties = append(duties, float64(high)/float64(period))
	}
	return periods, duties
}

func medianDuration(values []time.Duration) time.Duration {
	sorted := append([]time.Duration(nil), values...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })
	n := len(sorted)
	if n%2 == 1 {
		return sorted[n/2]
	}
	return (sorted[n/2-1] + sorted[n/2]) / 2
}

func medianFloat(values []float64) float64 {
	sorted := append([]float64(nil), values...)
	sort.Float64s(sorted)
	n := len(sorted)
	if n%2 == 1 {
		return sorted[n/2]
	}
	return (sorted[n/2-1] + sorted[n/2]) / 2
}

func TestRingingAgainWhileItRingsKeepsASingleTone(t *testing.T) {
	pin := &fakePin{}
	clk := newStepClock()
	ringer := newRinger(pin, clk, io.Discard)
	ringer.Ring()
	ringer.Ring()
	defer ringer.Stop()
	steps := recordRing(t, clk, pin, time.Second/32)
	if err := slice1200(steps); err != nil {
		t.Fatal(err)
	}
}

func take1200(take func(level int, wait time.Duration) error) error {
	for n := 0; n < 37; n++ {
		if err := take(1, pulseOn1200); err != nil {
			return err
		}
		if err := take(0, pulseOff1200); err != nil {
			return err
		}
	}
	if err := take(1, pulseOn1200); err != nil {
		return err
	}
	return take(0, pulseTail1200)
}

func slice1200(steps []ringStep) error {
	i := 0
	err := take1200(func(level int, wait time.Duration) error {
		if i >= len(steps) {
			return fmt.Errorf("%d ステップで音が尽きた", i+1)
		}
		got := steps[i]
		i++
		if got.level != level || got.wait != wait {
			return fmt.Errorf("ステップ %d = レベル %d を %s, want レベル %d を %s", i, got.level, got.wait, level, wait)
		}
		return nil
	})
	if err != nil {
		return err
	}
	if i != len(steps) {
		return fmt.Errorf("1200 Hz のあと %d ステップ余った", len(steps)-i)
	}
	return nil
}

// warble は、1,200 Hz と 1,600 Hz を 1/32 秒ずつ 16 対（1 秒）鳴らし、
// 2 秒休み、もう一度 1,200 Hz を 1/32 秒鳴らす並びである。
func warble(steps []ringStep) error {
	i := 0
	take := func(level int, wait time.Duration) error {
		if i >= len(steps) {
			return fmt.Errorf("%d ステップで音が尽きた", i+1)
		}
		got := steps[i]
		i++
		if got.level != level || got.wait != wait {
			return fmt.Errorf("ステップ %d = レベル %d を %s, want レベル %d を %s", i, got.level, got.wait, level, wait)
		}
		return nil
	}
	slice1200 := func() error {
		return take1200(take)
	}
	slice1600 := func() error {
		for n := 0; n < 50; n++ {
			if err := take(1, pulseOn1600); err != nil {
				return err
			}
			if err := take(0, pulseOff1600); err != nil {
				return err
			}
		}
		return nil
	}
	for n := 0; n < 16; n++ {
		if err := slice1200(); err != nil {
			return fmt.Errorf("%d 回目の 1200 Hz: %w", n+1, err)
		}
		if err := slice1600(); err != nil {
			return fmt.Errorf("%d 回目の 1600 Hz: %w", n+1, err)
		}
	}
	var quiet time.Duration
	for quiet < 2*time.Second {
		if i >= len(steps) {
			return fmt.Errorf("休みが %s で尽きた", quiet)
		}
		if steps[i].level != 0 {
			return fmt.Errorf("休みの %s で鳴った", quiet)
		}
		quiet += steps[i].wait
		i++
	}
	if quiet != 2*time.Second {
		return fmt.Errorf("休み = %s, want 2s", quiet)
	}
	if err := slice1200(); err != nil {
		return fmt.Errorf("休みのあとの 1200 Hz: %w", err)
	}
	if i != len(steps) {
		return fmt.Errorf("パターンのあと %d ステップ余った", len(steps)-i)
	}
	return nil
}

type ringStep struct {
	level int
	wait  time.Duration
}

// recordRing は、呼び出し音が時計を待つたびにその待ちを進め、線のレベルと待ち時間を残す。
func recordRing(t *testing.T, clk *stepClock, pin *fakePin, until time.Duration) []ringStep {
	t.Helper()
	start := clk.Now()
	var steps []ringStep
	for clk.Now().Sub(start) < until {
		clk.waitArmed(t)
		wait := clk.pendingFor()
		if wait <= 0 {
			t.Fatal("呼び出し音の待ち時間が 0")
		}
		if clk.Now().Sub(start)+wait > until {
			break
		}
		steps = append(steps, ringStep{level: pin.Level(), wait: wait})
		clk.Advance(wait)
	}
	return steps
}

// fakePin は、呼び出し音が駆動する GPIO の線である。
type fakePin struct {
	mu     sync.Mutex
	level  int
	closed bool
}

func (p *fakePin) Set(level int) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.closed {
		return fmt.Errorf("閉じた線に %d を出した", level)
	}
	p.level = level
	return nil
}

func (p *fakePin) Close() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.closed = true
	p.level = 0
	return nil
}

func (p *fakePin) Level() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.level
}

// timedPin は、線を入れたり切ったりした時刻を残す。
type timedPin struct {
	mu    sync.Mutex
	level int
	edges []pinEdge
}

type pinEdge struct {
	level int
	at    time.Time
}

func (p *timedPin) Set(level int) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if n := len(p.edges); n > 0 && p.edges[n-1].level == level {
		p.level = level
		return nil
	}
	p.level = level
	p.edges = append(p.edges, pinEdge{level: level, at: time.Now()})
	return nil
}

func (p *timedPin) Close() error { return nil }

func (p *timedPin) Level() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.level
}

func (p *timedPin) snapshot() []pinEdge {
	p.mu.Lock()
	defer p.mu.Unlock()
	out := make([]pinEdge, len(p.edges))
	copy(out, p.edges)
	return out
}

func (p *timedPin) cycles() int {
	periods, _ := cycleStats(p.snapshot(), 1<<20)
	return len(periods)
}

// stepClock は、呼び出し音が待つまで Advance を進めない時計である。
type stepClock struct {
	mu      sync.Mutex
	now     time.Time
	pending *stepTimer
	armed   chan struct{}
}

func newStepClock() *stepClock {
	return &stepClock{
		now:   time.Unix(0, 0),
		armed: make(chan struct{}, 1),
	}
}

func (c *stepClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *stepClock) NewTimer(d time.Duration) clock.Timer {
	c.mu.Lock()
	defer c.mu.Unlock()
	if d < 0 {
		d = 0
	}
	timer := &stepTimer{
		clock:    c,
		deadline: c.now.Add(d),
		ch:       make(chan time.Time, 1),
	}
	if d == 0 {
		timer.ch <- c.now
		return timer
	}
	c.pending = timer
	select {
	case c.armed <- struct{}{}:
	default:
	}
	return timer
}

func (c *stepClock) Advance(d time.Duration) {
	c.mu.Lock()
	c.now = c.now.Add(d)
	timer := c.pending
	var fire chan time.Time
	var now time.Time
	if timer != nil && !timer.stopped && !timer.deadline.After(c.now) {
		c.pending = nil
		fire = timer.ch
		now = c.now
	}
	c.mu.Unlock()
	if fire != nil {
		fire <- now
	}
}

func (c *stepClock) pendingFor() time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.pending == nil {
		return 0
	}
	return c.pending.deadline.Sub(c.now)
}

func (c *stepClock) hasPending() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.pending != nil && !c.pending.stopped
}

func (c *stepClock) waitArmed(t *testing.T) {
	t.Helper()
	select {
	case <-c.armed:
	case <-time.After(2 * time.Second):
		t.Fatal("呼び出し音が次の時間を待たなかった")
	}
}

type stepTimer struct {
	clock    *stepClock
	deadline time.Time
	ch       chan time.Time
	stopped  bool
}

func (t *stepTimer) Chan() <-chan time.Time { return t.ch }

func (t *stepTimer) Stop() {
	t.clock.mu.Lock()
	defer t.clock.mu.Unlock()
	t.stopped = true
	if t.clock.pending == t {
		t.clock.pending = nil
	}
}
