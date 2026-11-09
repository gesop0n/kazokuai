package pi

import (
	"bytes"
	"context"
	"encoding/binary"
	"strings"
	"testing"
	"time"

	"github.com/gesop0n/kazokuai/device/phone"
)

func TestSpeakerCheckPlaysAOneSecondTone(t *testing.T) {
	fake := &fakeEar{}
	var out bytes.Buffer
	err := runCheck(context.Background(), "speaker", hardware{
		out:  &out,
		open: func() (ear, error) { return fake, nil },
		tone: time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "耳から離して確認してください。") {
		t.Fatalf("表示 =\n%s", out.String())
	}
	if got, want := len(fake.played), phone.SpeakerSampleRate*2; got != want {
		t.Fatalf("音の長さ = %d バイト, want %d", got, want)
	}
	if sample(fake.played, 0) != 0 {
		t.Fatalf("始まり = %d, want 0", sample(fake.played, 0))
	}
	if got := maxAbs(fake.played); got < 3000 || got > 3277 {
		t.Fatalf("いちばん大きい音 = %d, want 0.1 前後", got)
	}
}

func TestMicCheckPlaysBackWhatItRecorded(t *testing.T) {
	// 16 kHz で 1 周期の波を、24 kHz でも同じ時間・同じ高さになるサンプル数で再生する。
	mic := pcm16(16384, 0, -16384, 0)
	fake := &fakeEar{mic: mic}
	var out bytes.Buffer
	err := runCheck(context.Background(), "mic", hardware{
		out:    &out,
		open:   func() (ear, error) { return fake, nil },
		record: 15 * time.Millisecond,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "ピーク: 0.5000") {
		t.Fatalf("表示 =\n%s", out.String())
	}
	wantN := len(mic) / 2 * phone.SpeakerSampleRate / phone.MicSampleRate
	if got := len(fake.played) / 2; got != wantN {
		t.Fatalf("再生 = %d サンプル, want %d。録音と同じ時間になる", got, wantN)
	}
	want := pcm16(16384, 5461, -5461, -16384, -5461, 0)
	if !bytes.Equal(fake.played, want) {
		t.Fatalf("再生 = %v, want %v", samples(fake.played), samples(want))
	}
}

func TestMicCheckSaysWhenNothingWasRecorded(t *testing.T) {
	fake := &fakeEar{empty: true}
	var out bytes.Buffer
	err := runCheck(context.Background(), "mic", hardware{
		out:    &out,
		open:   func() (ear, error) { return fake, nil },
		record: time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "録音データがありません。") {
		t.Fatalf("表示 =\n%s", out.String())
	}
	if len(fake.played) != 0 {
		t.Fatal("録音が無いのに再生した")
	}
}

func TestDeviceCheckPrintsTheList(t *testing.T) {
	var out bytes.Buffer
	err := runCheck(context.Background(), "devices", hardware{
		out:  &out,
		list: func() (string, error) { return "再生:\n  USB Audio\n", nil },
	})
	if err != nil {
		t.Fatal(err)
	}
	if out.String() != "再生:\n  USB Audio\n" {
		t.Fatalf("一覧 =\n%s", out.String())
	}
}

type fakeEar struct {
	played []byte
	mic    []byte
	empty  bool
}

func (f *fakeEar) Play(pcm []byte) { f.played = append(f.played, pcm...) }
func (f *fakeEar) Hush()           { f.played = nil }
func (f *fakeEar) Playing() bool   { return false }
func (f *fakeEar) Close()          {}

func (f *fakeEar) Listen(ctx context.Context) (<-chan []byte, error) {
	ch := make(chan []byte, 1)
	if f.empty {
		close(ch)
		return ch, nil
	}
	ch <- append([]byte(nil), f.mic...)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func pcm16(samples ...int16) []byte {
	buf := make([]byte, len(samples)*2)
	for i, s := range samples {
		binary.LittleEndian.PutUint16(buf[i*2:], uint16(s))
	}
	return buf
}

func sample(buf []byte, i int) int16 {
	return int16(binary.LittleEndian.Uint16(buf[i*2:]))
}

func samples(buf []byte) []int16 {
	out := make([]int16, len(buf)/2)
	for i := range out {
		out[i] = sample(buf, i)
	}
	return out
}

func maxAbs(buf []byte) int {
	max := 0
	for i := 0; i+1 < len(buf); i += 2 {
		s := int(sample(buf, i/2))
		if s < 0 {
			s = -s
		}
		if s > max {
			max = s
		}
	}
	return max
}
