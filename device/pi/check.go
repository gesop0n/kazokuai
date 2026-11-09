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
	bell   func() (bell, error)
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
	case "ringer":
		err = checkRinger(ctx, hw)
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
	h.Play(recording)
	return waitUntilQuiet(ctx, h, hw.record+time.Second, hw.tail)
}

// bell は、確認が止めるまで鳴らす呼び出し音である。
type bell interface {
	Ring()
	Close() error
}

func checkRinger(ctx context.Context, hw hardware) error {
	if hw.bell == nil {
		return errors.New("呼び出し音がありません")
	}
	ringer, err := hw.bell()
	if err != nil {
		return err
	}
	defer ringer.Close()
	fmt.Fprintln(hw.out, "本体のスピーカーを鳴らします。Ctrl+C で止めます。")
	ringer.Ring()
	<-ctx.Done()
	return ctx.Err()
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
