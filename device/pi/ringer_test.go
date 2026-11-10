package pi

import (
	"bytes"
	"fmt"
	"io"
	"runtime"
	"sort"
	"sync"
	"syscall"
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
	// 機械が忙しすぎて短い待ちを保てないとき、測っているあいだに CPU が回らなかったとき、
	// 止めるゴルーチンが動き出せないときも、この測定だけを飛ばす。幅は変えない。
	// タイマー待ちの音程は、忙しくなくても失敗する。
	if testing.Short() {
		t.Skip("実時計の音程は -short では測らない")
	}
	t.Run("1200", func(t *testing.T) {
		var lastStop time.Duration
		var lastErr error
		var cycles int
		for attempt := 0; attempt < realPitchAttempts; attempt++ {
			skipIfClockTooBusy(t, 1200)
			pin := &timedPin{}
			ringer := newRinger(pin, clock.Real{}, io.Discard)
			ringer.Ring()
			if !waitForCycles(pin, 12) {
				ringer.Stop()
				cycles = pin.cycles()
				continue
			}
			started := time.Now()
			ringer.Stop()
			lastStop = time.Since(started)
			if lastStop > 20*time.Millisecond {
				continue
			}
			if pin.Level() != 0 {
				t.Fatal("止めたあとも鳴っている")
			}
			periods, duties := cycleStats(pin.snapshot(), 12)
			if err := pitchError(1200, periods, duties); err != nil {
				lastErr = err
				if measurementWasPreempted(1200, periods, duties) {
					continue
				}
				skipIfClockTooBusy(t, 1200)
				t.Fatal(err)
			}
			return
		}
		if schedulerSlow(20*time.Millisecond) || clockTooBusyForPitch(time.Second/1200) {
			t.Skip("実時計の音程は、この機械が忙しくて測れない")
		}
		if lastStop > 20*time.Millisecond {
			t.Fatalf("止めるのに %s かかった", lastStop)
		}
		if lastErr != nil {
			t.Fatal(lastErr)
		}
		t.Fatalf("周期が %d しかなかった", cycles)
	})
	t.Run("1600", func(t *testing.T) {
		runtime.LockOSThread()
		defer runtime.UnlockOSThread()
		for attempt := 0; attempt < realPitchAttempts; attempt++ {
			if clockTooBusyForPitch(time.Second / 1600) {
				t.Skip("実時計の音程は、この機械が忙しくて測れない")
			}
			pin := &timedPin{}
			ringer := newRinger(pin, clock.Real{}, io.Discard)
			cpu0, ok0 := procCPU()
			started := time.Now()
			if !ringer.tone(make(chan struct{}), ringerHighHz, realPitchWindow) {
				t.Fatal("1,600 Hz が途中で止まった")
			}
			wall := time.Since(started)
			cpu1, ok1 := procCPU()
			cpu := wall
			if ok0 && ok1 && cpu1 >= cpu0 {
				cpu = cpu1 - cpu0
			}
			periods, duties := cycleStats(pin.snapshot(), 12)
			err := pitchError(1600, periods, duties)
			if err == nil {
				return
			}
			// タイマー待ちは CPU を使わず、周期が揃ってデューティー比が約 50% になる。
			// それは音程の失敗なので、忙しさでは飛ばさない。
			if timerPitch(1600, periods, duties) {
				t.Fatal(err)
			}
			if measurementWasPreempted(1600, periods, duties) || cpuStarved(wall, cpu) {
				continue
			}
			if clockTooBusyForPitch(time.Second / 1600) {
				t.Skip("実時計の音程は、この機械が忙しくて測れない")
			}
			t.Fatal(err)
		}
		t.Skip("実時計の音程は、この機械が忙しくて測れない")
	})
}

// realPitchLow と realPitchHigh は、実測の音程が指定の何倍までならよいかである。
const (
	realPitchLow      = 0.7
	realPitchHigh     = 1.3
	realPitchWindow   = 15 * time.Millisecond
	realPitchAttempts = 5
)

// skipIfClockTooBusy は、hz の周期と同じ長さの待ちを実時計が保てないとき、実時計の測定を飛ばす。
// 呼び出し音の実測が外れたことでは飛ばさない。
func skipIfClockTooBusy(t *testing.T, hz int) {
	t.Helper()
	if clockTooBusyForPitch(time.Second / time.Duration(hz)) {
		t.Skip("実時計の音程は、この機械が忙しくて測れない")
	}
}

// clockTooBusyForPitch は、音程を測るのと同じ長さのあいだ period の待ちを回し、
// 8 回分も入らないか、入った待ちの中央値が音程の下限より長いかである。
// 呼び出し音は見ない。静かな機械では、15 ミリ秒に 1,600 Hz が 20 回以上入る。
func clockTooBusyForPitch(period time.Duration) bool {
	const samples = 32
	elapsed := make([]time.Duration, 0, samples)
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	end := time.Now().Add(realPitchWindow)
	for len(elapsed) < samples && time.Now().Before(end) {
		start := time.Now()
		deadline := start.Add(period)
		for time.Now().Before(deadline) {
		}
		elapsed = append(elapsed, time.Since(start))
	}
	if len(elapsed) < 8 {
		return true
	}
	return spinsTooSlow(elapsed, period)
}

// spinsTooSlow は、待ちの中央値が音程の下限（period/0.7）より長いかである。
func spinsTooSlow(elapsed []time.Duration, period time.Duration) bool {
	if len(elapsed) == 0 || period <= 0 {
		return true
	}
	limit := time.Duration(float64(period) / realPitchLow)
	return medianDuration(elapsed) > limit
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

func waitForCycles(pin *timedPin, n int) bool {
	deadline := time.Now().Add(200 * time.Millisecond)
	for pin.cycles() < n {
		if time.Now().After(deadline) {
			return false
		}
		time.Sleep(time.Millisecond)
	}
	return true
}

// cpuStarved は、壁時計だけが進んで、このプロセスが半分も回っていなかったときである。
func cpuStarved(wall, cpu time.Duration) bool {
	return wall > 5*time.Millisecond && cpu*2 < wall
}

func procCPU() (time.Duration, bool) {
	var usage syscall.Rusage
	if err := syscall.Getrusage(syscall.RUSAGE_SELF, &usage); err != nil {
		return 0, false
	}
	return time.Duration(usage.Utime.Nano() + usage.Stime.Nano()), true
}

// schedulerSlow は、別のゴルーチンが limit 以内に動き出せないときである。
func schedulerSlow(limit time.Duration) bool {
	start := time.Now()
	done := make(chan struct{})
	go func() { close(done) }()
	timer := time.NewTimer(limit)
	defer timer.Stop()
	select {
	case <-done:
		return time.Since(start) > limit
	case <-timer.C:
		return true
	}
}

// timerPitch は、周期が揃って遅く、デューティー比が約 50% のときである。
// タイマー待ちの音程で、忙しさでは飛ばさない。
func timerPitch(hz int, periods []time.Duration, duties []float64) bool {
	if len(periods) < 3 || len(duties) != len(periods) {
		return false
	}
	med := medianDuration(periods)
	if med <= 0 {
		return false
	}
	for _, period := range periods {
		if period*2 < med || period > med*2 {
			return false
		}
	}
	freq := float64(time.Second) / float64(med)
	lo, hi := float64(hz)*realPitchLow, float64(hz)*realPitchHigh
	if freq >= lo && freq <= hi {
		return false
	}
	duty := medianFloat(duties)
	return duty >= 0.30 && duty <= 0.70
}

// measurementWasPreempted は、8 回分の周期が取れず、音程の幅に入った周期と、
// 待ちで伸びた周期が混じっているときである。幅に入った周期のデューティー比も見る。
// どの周期も幅の外なら、音程そのものが外れているので、ここでは飛ばさない。
func measurementWasPreempted(hz int, periods []time.Duration, duties []float64) bool {
	if len(periods) == 0 || len(periods) >= 8 || len(duties) != len(periods) {
		return false
	}
	lo, hi := periodBounds(hz)
	inBand := make([]float64, 0, len(duties))
	stalled := false
	for i, period := range periods {
		switch {
		case period >= lo && period <= hi:
			inBand = append(inBand, duties[i])
		case period > hi:
			stalled = true
		}
	}
	if !stalled || len(inBand) == 0 {
		return false
	}
	duty := medianFloat(inBand)
	return duty >= 0.04 && duty <= 0.25
}

func periodBounds(hz int) (lo, hi time.Duration) {
	period := float64(time.Second / time.Duration(hz))
	return time.Duration(period / realPitchHigh), time.Duration(period / realPitchLow)
}

func pitchError(hz int, periods []time.Duration, duties []float64) error {
	if len(periods) < 8 {
		return fmt.Errorf("%d Hz の周期が %d しかなかった", hz, len(periods))
	}
	freq := float64(time.Second) / float64(medianDuration(periods))
	duty := medianFloat(duties)
	lo, hi := float64(hz)*realPitchLow, float64(hz)*realPitchHigh
	if freq < lo || freq > hi {
		return fmt.Errorf("%d Hz の実測 = %.0f Hz, 許容 %.0f–%.0f。デューティー比 = %.1f%%", hz, freq, lo, hi, duty*100)
	}
	if duty < 0.04 || duty > 0.25 {
		return fmt.Errorf("%d Hz のデューティー比 = %.1f%%, 許容 4–25%%。実測 = %.0f Hz", hz, duty*100, freq)
	}
	return nil
}

func TestSpinsTooSlowUsesThePitchBound(t *testing.T) {
	period := time.Second / 1600
	if spinsTooSlow([]time.Duration{period, period, period}, period) {
		t.Fatal("指定どおりの待ちを、忙しすぎるとした")
	}
	// 0.7 倍の音程は、周期が 1/0.7 倍まで伸びることである。そこまでは測れる。
	within := time.Duration(float64(period) / realPitchLow)
	if spinsTooSlow([]time.Duration{within, within, within}, period) {
		t.Fatal("許容の下限の待ちを、忙しすぎるとした")
	}
	if !spinsTooSlow([]time.Duration{within + time.Nanosecond, within + time.Nanosecond, within + time.Nanosecond}, period) {
		t.Fatal("許容を超えた待ちを測れるとした")
	}
}

func TestMeasurementWasPreemptedNeedsAStallAndTheRightPitch(t *testing.T) {
	period := time.Second / 1600
	duty := []float64{0.10, 0.10, 0.10, 0.10, 0.01}
	held := []time.Duration{period, period, period, period, 12 * time.Millisecond}
	if !measurementWasPreempted(1600, held, duty) {
		t.Fatal("幅に入った周期と、待ちで伸びた周期を、測れるとした")
	}
	timer := []time.Duration{4 * time.Millisecond, 4 * time.Millisecond, 4 * time.Millisecond, 4 * time.Millisecond}
	timerDuty := []float64{0.50, 0.50, 0.50, 0.50}
	if measurementWasPreempted(1600, timer, timerDuty) {
		t.Fatal("幅の外の音程を、忙しさで飛ばすとした")
	}
	enough := []time.Duration{period, period, period, period, period, period, period, period}
	enoughDuty := []float64{0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10}
	if measurementWasPreempted(1600, enough, enoughDuty) {
		t.Fatal("8 回分取れた測定を、忙しさで飛ばすとした")
	}
	wrongDuty := []float64{0.50, 0.50, 0.50, 0.50, 0.50}
	if measurementWasPreempted(1600, held, wrongDuty) {
		t.Fatal("デューティー比が外れた測定を、忙しさで飛ばすとした")
	}
}

func TestCPUStarvedWhenTheProcessDidNotRun(t *testing.T) {
	if cpuStarved(15*time.Millisecond, 15*time.Millisecond) {
		t.Fatal("回していた時間を、待たされたとした")
	}
	if cpuStarved(15*time.Millisecond, 8*time.Millisecond) {
		t.Fatal("半分より長く回した時間を、待たされたとした")
	}
	if !cpuStarved(15*time.Millisecond, 2*time.Millisecond) {
		t.Fatal("ほとんど回っていない時間を、測れるとした")
	}
	if cpuStarved(time.Millisecond, 0) {
		t.Fatal("短すぎる測定を、待たされたとした")
	}
}

func TestTimerPitchIsTheSlowEvenDuty(t *testing.T) {
	slow := []time.Duration{4 * time.Millisecond, 4 * time.Millisecond, 4 * time.Millisecond, 4 * time.Millisecond}
	half := []float64{0.50, 0.50, 0.50, 0.50}
	if !timerPitch(1600, slow, half) {
		t.Fatal("タイマー待ちの音程を、忙しさで飛ばせるとした")
	}
	stalled := []time.Duration{time.Second / 1600, 12 * time.Millisecond, 12 * time.Millisecond}
	low := []float64{0.10, 0.01, 0.01}
	if timerPitch(1600, stalled, low) {
		t.Fatal("待ちで伸びた周期を、タイマー待ちの音程とした")
	}
	if timerPitch(1600, nil, nil) {
		t.Fatal("周期がないのを、タイマー待ちの音程とした")
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
