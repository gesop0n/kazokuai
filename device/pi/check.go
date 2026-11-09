package pi

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math"
	"time"

	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/internal/clock"
)

// ear は、確認コマンドが使う受話器である。
type ear interface {
	Listen(ctx context.Context) (<-chan []byte, error)
	Play(pcm []byte)
	Hush()
	Playing() bool
	Close()
}

// hardware は、確認コマンドの向こうにある部品である。テストは偽物を渡す。
type hardware struct {
	out    io.Writer
	cfg    Config
	list   func() (string, error)
	open   func() (ear, error)
	line   func() (Line, error)
	record time.Duration
	tail   time.Duration
	tone   time.Duration
}

func runCheck(ctx context.Context, part string, hw hardware) error {
	var err error
	switch part {
	case "devices":
		err = checkDevices(hw)
	case "speaker":
		err = checkSpeaker(ctx, hw)
	case "mic":
		err = checkMic(ctx, hw)
	case "hook":
		err = checkHook(ctx, hw)
	case "keypad":
		err = checkKeypad(ctx, hw)
	default:
		err = fmt.Errorf("確認できない部品です: %s", part)
	}
	if errors.Is(err, context.Canceled) {
		fmt.Fprintln(hw.out, "停止しました。")
		return nil
	}
	return err
}

func checkDevices(hw hardware) error {
	text, err := hw.list()
	if err != nil {
		return err
	}
	fmt.Fprint(hw.out, text)
	return nil
}

func checkSpeaker(ctx context.Context, hw hardware) error {
	h, err := hw.open()
	if err != nil {
		return err
	}
	defer h.Close()
	fmt.Fprintln(hw.out, "受話器にテスト音を流します。耳から離して確認してください。")
	h.Play(tone(phone.SpeakerSampleRate, hw.tone))
	return waitUntilQuiet(ctx, h, hw.tone+time.Second, hw.tail)
}

func checkMic(ctx context.Context, hw hardware) error {
	h, err := hw.open()
	if err != nil {
		return err
	}
	defer h.Close()
	fmt.Fprintln(hw.out, "5秒間、受話器に話してください。録音後に再生します。")
	recCtx, cancel := context.WithTimeout(ctx, hw.record)
	defer cancel()
	frames, err := h.Listen(recCtx)
	if err != nil {
		return err
	}
	var recording []byte
	for frame := range frames {
		recording = append(recording, frame...)
	}
	if len(recording) == 0 {
		fmt.Fprintln(hw.out, "録音データがありません。入力機器を確認してください。")
		return nil
	}
	fmt.Fprintf(hw.out, "ピーク: %.4f\n", peak(recording))
	// マイクは 16 kHz、スピーカーは 24 kHz である。そのまま流すと、5 秒が約 3.3 秒になり、声が高くなる。
	h.Play(toSpeakerRate(recording))
	return waitUntilQuiet(ctx, h, hw.record+time.Second, hw.tail)
}

func checkHook(ctx context.Context, hw hardware) error {
	line, err := hw.line()
	if err != nil {
		return err
	}
	defer line.Close()
	return Watch(ctx, line, hw.cfg.LiftedWhenClosed, hw.cfg.Debounce, clock.Real{}, hw.out)
}

func waitUntilQuiet(ctx context.Context, h ear, limit, tail time.Duration) error {
	deadline := time.Now().Add(limit)
	for h.Playing() {
		if err := ctx.Err(); err != nil {
			return err
		}
		if time.Now().After(deadline) {
			return errors.New("受話器の再生が終わりません")
		}
		timer := time.NewTimer(10 * time.Millisecond)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-timer.C:
		}
	}
	if tail <= 0 {
		return nil
	}
	timer := time.NewTimer(tail)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

// tone は、1 秒の確認音である。振幅 0.1 の 440 Hz で、両端を 20ms かけて消す。
// 受話器が、これに倍率を掛けて上限で切る。
func tone(rate int, duration time.Duration) []byte {
	if rate <= 0 {
		rate = phone.SpeakerSampleRate
	}
	n := int(duration.Seconds() * float64(rate))
	if n < 1 {
		n = 1
	}
	buf := make([]byte, n*2)
	fade := rate / 50
	if fade < 1 {
		fade = 1
	}
	for i := 0; i < n; i++ {
		amp := 0.1 * math.Sin(2*math.Pi*440*float64(i)/float64(rate))
		if i < fade {
			amp *= float64(i) / float64(fade)
		}
		tail := n - 1 - i
		if tail < fade {
			amp *= float64(tail) / float64(fade)
		}
		sample := int(math.Round(amp * 32767))
		binary.LittleEndian.PutUint16(buf[i*2:], uint16(int16(sample)))
	}
	return buf
}

// toSpeakerRate は、マイクの 16 kHz をスピーカーの 24 kHz に直す。録音と同じ時間、同じ高さで鳴る。
func toSpeakerRate(pcm []byte) []byte {
	in := len(pcm) / 2
	if in == 0 {
		return nil
	}
	outN := in * phone.SpeakerSampleRate / phone.MicSampleRate
	if outN == 0 {
		return nil
	}
	buf := make([]byte, outN*2)
	denom := phone.SpeakerSampleRate
	for i := 0; i < outN; i++ {
		numer := i * phone.MicSampleRate
		i0 := numer / denom
		frac := numer % denom
		s0 := int(pcmSample(pcm, i0, in))
		s1 := int(pcmSample(pcm, i0+1, in))
		v := s0*(denom-frac) + s1*frac
		binary.LittleEndian.PutUint16(buf[i*2:], uint16(int16(divRound(v, denom))))
	}
	return buf
}

func pcmSample(pcm []byte, index, n int) int16 {
	if index >= n {
		index = n - 1
	}
	if index < 0 {
		index = 0
	}
	return int16(binary.LittleEndian.Uint16(pcm[index*2:]))
}

func divRound(v, denom int) int {
	if v >= 0 {
		return (v + denom/2) / denom
	}
	return -((-v + denom/2) / denom)
}

func peak(pcm []byte) float64 {
	var max float64
	for i := 0; i+1 < len(pcm); i += 2 {
		s := math.Abs(float64(int16(binary.LittleEndian.Uint16(pcm[i:]))) / float64(fullScale))
		if s > max {
			max = s
		}
	}
	return max
}

// fullScale は、16 ビットの 1.0 である。handset と同じ 32768。
const fullScale = 32768
