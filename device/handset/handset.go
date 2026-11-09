// Package handset は、malgo で受話器のマイクとスピーカーを開く。
//
// Mac は既定の機器を 1 チャンネルのまま使う。電話機は USB のアダプターを名前で選び、
// マイクは設定したチャンネルを、スピーカーは両方のチャンネルに同じ音を、決まった倍率と上限で出す。
// どちらの速さへの変換も malgo に任せる。
package handset

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"math"
	"sync"
	"unsafe"

	"github.com/gen2brain/malgo"

	"github.com/gesop0n/kazokuai/device/phone"
)

// micPeriod は、マイクの音を 1 回に送る長さ(ミリ秒)である。
const micPeriod = 40

// fullScale は、16 ビット符号付きの 1.0 である。32767 ではなく 32768 にする。
const fullScale = 32768

// Options は、受話器の開き方である。
type Options struct {
	// DeviceName は、USB アダプターの名前に含まれる文字列である。空なら既定の機器を 1 チャンネルで使う。
	DeviceName string
	// MicChannel は、マイクが 2 チャンネルあるときに使うチャンネルである。0 が最初のチャンネル。
	MicChannel int
	// Gain は、スピーカーの音に掛ける倍率である。0 なら Mac と同じく、音を変えない。
	Gain float64
	// Limit は、フルスケールに対するスピーカーの上限である。Gain と揃えて 0 より大きいときだけ切る。
	Limit float64
}

// Handset は受話器の音声である。
type Handset struct {
	ctx     *malgo.AllocatedContext
	speaker *malgo.Device
	mics    sync.WaitGroup

	mu    sync.Mutex
	queue []byte

	speakerChannels int
	micChannels     int
	micChannel      int
	gain            float64
	limit           float64
	playbackID      unsafe.Pointer
	captureID       unsafe.Pointer
}

// Open はスピーカーを開く。マイクは Listen で開く。
func Open(opts Options) (*Handset, error) {
	if opts.MicChannel < 0 {
		return nil, errors.New("マイクのチャンネルが負です")
	}
	ctx, err := malgo.InitContext(nil, malgo.ContextConfig{}, nil)
	if err != nil {
		return nil, fmt.Errorf("音声を使えなかった: %w", err)
	}
	h := &Handset{
		ctx:             ctx,
		speakerChannels: 1,
		micChannels:     1,
		micChannel:      opts.MicChannel,
		gain:            opts.Gain,
		limit:           opts.Limit,
	}
	if opts.DeviceName != "" {
		if err := h.useNamedDevice(opts.DeviceName); err != nil {
			h.Close()
			return nil, err
		}
	}
	if err := h.openSpeaker(); err != nil {
		h.Close()
		return nil, fmt.Errorf("スピーカーを開けなかった: %w", err)
	}
	return h, nil
}

func (h *Handset) useNamedDevice(name string) error {
	playback, err := list(h.ctx, malgo.Playback)
	if err != nil {
		return err
	}
	capture, err := list(h.ctx, malgo.Capture)
	if err != nil {
		return err
	}
	out, err := choose(names(playback), name)
	if err != nil {
		return err
	}
	in, err := choose(names(capture), name)
	if err != nil {
		return err
	}
	h.playbackID = cDeviceID(playback[out].id)
	h.captureID = cDeviceID(capture[in].id)
	h.speakerChannels = atMostTwo(playback[out].Channels)
	h.micChannels = atMostTwo(capture[in].Channels)
	if h.micChannel >= h.micChannels {
		return fmt.Errorf("マイクのチャンネル %d は、%d チャンネルの機器にはありません", h.micChannel, h.micChannels)
	}
	return nil
}

func (h *Handset) openSpeaker() error {
	channels := h.speakerChannels
	dev, err := h.initPlayback(channels)
	if err != nil && channels > 1 {
		dev, err = h.initPlayback(1)
		channels = 1
	}
	if err != nil {
		return err
	}
	if err := dev.Start(); err != nil {
		dev.Uninit()
		return err
	}
	h.speaker = dev
	h.speakerChannels = channels
	return nil
}

func (h *Handset) initPlayback(channels int) (*malgo.Device, error) {
	config := malgo.DefaultDeviceConfig(malgo.Playback)
	config.Playback.Format = malgo.FormatS16
	config.Playback.Channels = uint32(channels)
	config.Playback.DeviceID = h.playbackID
	config.SampleRate = phone.SpeakerSampleRate
	return malgo.InitDevice(h.ctx.Context, config, malgo.DeviceCallbacks{Data: h.fill})
}

// fill は、スピーカーに流す音を queue から渡す。queue が空なら無音を渡す。
// 倍率が付いているときは、掛けてから上限を超えた部分を切り、全部のチャンネルに同じ音を出す。
func (h *Handset) fill(out, _ []byte, _ uint32) {
	if h.speakerChannels <= 1 && h.gain == 0 && h.limit == 0 {
		h.mu.Lock()
		n := copy(out, h.queue)
		h.queue = h.queue[n:]
		h.mu.Unlock()
		clear(out[n:])
		return
	}
	channels := h.speakerChannels
	if channels < 1 {
		channels = 1
	}
	frames := len(out) / (channels * 2)
	need := frames * 2
	h.mu.Lock()
	n := need
	if n > len(h.queue) {
		n = len(h.queue) &^ 1
	}
	mono := append([]byte(nil), h.queue[:n]...)
	h.queue = h.queue[n:]
	h.mu.Unlock()
	copied := copy(out, duplicate(scale(mono, h.gain, h.limit), channels))
	clear(out[copied:])
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

// Playing は、まだスピーカーに渡していない音があるとき真である。
// 機器の中に残っている音は含まない。
func (h *Handset) Playing() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.queue) > 0
}

func (h *Handset) Listen(ctx context.Context) (<-chan []byte, error) {
	frames := make(chan []byte, 32)
	var mu sync.Mutex
	closed := false
	callback := func(channels int) malgo.DataProc {
		return func(_, in []byte, _ uint32) {
			mu.Lock()
			defer mu.Unlock()
			if closed {
				return
			}
			var samples []byte
			if channels > 1 {
				samples = channel(in, channels, h.micChannel)
			} else {
				// in は malgo の持つメモリなので、写してから渡す
				samples = append([]byte(nil), in...)
			}
			select {
			case frames <- samples:
			default:
				// 送るのが追いつかないときは、古い音を待たせずに捨てる
			}
		}
	}

	channels := h.micChannels
	mic, err := h.initCapture(channels, callback(channels))
	if err != nil && channels > 1 && h.micChannel == 0 {
		channels = 1
		mic, err = h.initCapture(channels, callback(channels))
	}
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

func (h *Handset) initCapture(channels int, data malgo.DataProc) (*malgo.Device, error) {
	config := malgo.DefaultDeviceConfig(malgo.Capture)
	config.Capture.Format = malgo.FormatS16
	config.Capture.Channels = uint32(channels)
	config.Capture.DeviceID = h.captureID
	config.SampleRate = phone.MicSampleRate
	config.PeriodSizeInMilliseconds = micPeriod
	return malgo.InitDevice(h.ctx.Context, config, malgo.DeviceCallbacks{Data: data})
}

// Close はスピーカーを閉じ、音声を使い終える。開いているマイクがあれば、Listen に渡した ctx が終わって
// マイクが閉じるのを待つ。malgo では、使っている機器が残っている間に音声を使い終えてはいけない。
func (h *Handset) Close() {
	if h == nil {
		return
	}
	h.mics.Wait()
	if h.speaker != nil {
		h.speaker.Uninit()
		h.speaker = nil
	}
	if h.ctx != nil {
		h.ctx.Uninit()
		h.ctx.Free()
		h.ctx = nil
	}
	freeID(h.playbackID)
	freeID(h.captureID)
	h.playbackID = nil
	h.captureID = nil
}

// scale は、モノラルの 16 ビット音声に倍率を掛け、フルスケールの上限を超えた部分を切る。
func scale(pcm []byte, gain, limit float64) []byte {
	out := make([]byte, len(pcm)&^1)
	ceil := limit * fullScale
	for i := 0; i+1 < len(pcm); i += 2 {
		v := float64(int16(binary.LittleEndian.Uint16(pcm[i:]))) * gain
		if v > ceil {
			v = ceil
		} else if v < -ceil {
			v = -ceil
		}
		n := int(math.Round(v))
		if n > math.MaxInt16 {
			n = math.MaxInt16
		} else if n < math.MinInt16 {
			n = math.MinInt16
		}
		binary.LittleEndian.PutUint16(out[i:], uint16(int16(n)))
	}
	return out
}

// duplicate は、モノラルの音を channels 個のチャンネルに同じ値で並べる。
func duplicate(mono []byte, channels int) []byte {
	if channels <= 1 {
		return mono
	}
	frames := len(mono) / 2
	out := make([]byte, frames*channels*2)
	for i := 0; i < frames; i++ {
		sample := mono[i*2 : i*2+2]
		for c := 0; c < channels; c++ {
			copy(out[(i*channels+c)*2:], sample)
		}
	}
	return out
}

// channel は、インターリーブされた 16 ビット音声から 1 チャンネルを取り出す。
func channel(pcm []byte, channels, index int) []byte {
	if channels <= 1 {
		return append([]byte(nil), pcm...)
	}
	frames := len(pcm) / (channels * 2)
	out := make([]byte, frames*2)
	for i := 0; i < frames; i++ {
		copy(out[i*2:], pcm[(i*channels+index)*2:])
	}
	return out
}

func cDeviceID(id malgo.DeviceID) unsafe.Pointer {
	return C.CBytes(id[:])
}

func freeID(p unsafe.Pointer) {
	if p != nil {
		C.free(p)
	}
}
