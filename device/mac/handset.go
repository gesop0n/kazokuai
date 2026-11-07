// Package mac は、Mac で電話機の代わりをする。受話器の音声は既定のマイクとスピーカー、
// フックは Enter キー、呼び出し音とランプはターミナルの文字である。
//
// macOS の malgo にはエコーキャンセルがないので、イヤホンを付けて使う。
package mac

import (
	"context"
	"fmt"
	"sync"

	"github.com/gen2brain/malgo"

	"github.com/gesop0n/kazokuai/device/phone"
)

// micPeriod は、マイクの音を 1 回に送る長さ(ミリ秒)である。
const micPeriod = 40

// Handset は、malgo で既定のマイクとスピーカーを使う受話器の音声である。
// マイクは phone.MicSampleRate、スピーカーは phone.SpeakerSampleRate で別々に開き、
// Mac の機器の速さへの変換は malgo に任せる。
type Handset struct {
	ctx     *malgo.AllocatedContext
	speaker *malgo.Device
	// mics は、開いているマイクである。音声を使い終える前に、すべて閉じるのを待つ。
	mics sync.WaitGroup

	mu sync.Mutex
	// queue は、まだスピーカーで流していない音である。
	queue []byte
}

// OpenHandset はスピーカーを開く。マイクは Listen で開く。
func OpenHandset() (*Handset, error) {
	ctx, err := malgo.InitContext(nil, malgo.ContextConfig{}, nil)
	if err != nil {
		return nil, fmt.Errorf("音声を使えなかった: %w", err)
	}
	h := &Handset{ctx: ctx}

	config := malgo.DefaultDeviceConfig(malgo.Playback)
	config.Playback.Format = malgo.FormatS16
	config.Playback.Channels = 1
	config.SampleRate = phone.SpeakerSampleRate
	h.speaker, err = malgo.InitDevice(ctx.Context, config, malgo.DeviceCallbacks{Data: h.fill})
	if err == nil {
		err = h.speaker.Start()
	}
	if err != nil {
		h.Close()
		return nil, fmt.Errorf("スピーカーを開けなかった: %w", err)
	}
	return h, nil
}

// fill は、スピーカーに流す音を queue から渡す。queue が空なら無音を渡す。
func (h *Handset) fill(out, _ []byte, _ uint32) {
	h.mu.Lock()
	n := copy(out, h.queue)
	h.queue = h.queue[n:]
	h.mu.Unlock()
	clear(out[n:])
}

func (h *Handset) Play(pcm []byte) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.queue = append(h.queue, pcm...)
}

func (h *Handset) Hush() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.queue = nil
}

func (h *Handset) Listen(ctx context.Context) (<-chan []byte, error) {
	frames := make(chan []byte, 32)
	var mu sync.Mutex
	closed := false

	config := malgo.DefaultDeviceConfig(malgo.Capture)
	config.Capture.Format = malgo.FormatS16
	config.Capture.Channels = 1
	config.SampleRate = phone.MicSampleRate
	config.PeriodSizeInMilliseconds = micPeriod
	mic, err := malgo.InitDevice(h.ctx.Context, config, malgo.DeviceCallbacks{
		Data: func(_, in []byte, _ uint32) {
			mu.Lock()
			defer mu.Unlock()
			if closed {
				return
			}
			// in は malgo の持つメモリなので、写してから渡す
			select {
			case frames <- append([]byte(nil), in...):
			default:
				// 送るのが追いつかないときは、古い音を待たせずに捨てる
			}
		},
	})
	if err != nil {
		return nil, fmt.Errorf("マイクを開けなかった: %w", err)
	}
	if err := mic.Start(); err != nil {
		mic.Uninit()
		return nil, fmt.Errorf("マイクを開けなかった: %w", err)
	}
	h.mics.Add(1)
	go func() {
		defer h.mics.Done()
		<-ctx.Done()
		mic.Uninit()
		mu.Lock()
		defer mu.Unlock()
		closed = true
		close(frames)
	}()
	return frames, nil
}

// Close はスピーカーを閉じ、音声を使い終える。開いているマイクがあれば、Listen に渡した ctx が終わって
// マイクが閉じるのを待つ。malgo では、使っている機器が残っている間に音声を使い終えてはいけない。
func (h *Handset) Close() {
	h.mics.Wait()
	if h.speaker != nil {
		h.speaker.Uninit()
	}
	h.ctx.Uninit()
	h.ctx.Free()
}
