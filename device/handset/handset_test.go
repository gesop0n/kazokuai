package handset

import (
	"encoding/binary"
	"testing"
)

func TestQuietSpeechKeepsTheSetVolumeOnBothEars(t *testing.T) {
	h := &Handset{speakerChannels: 2, gain: 0.15, limit: 0.1}
	h.Play(pcm(1000))

	out := make([]byte, 4)
	h.fill(out, nil, 1)

	if got, want := sampleAt(out, 0), int16(150); got != want {
		t.Fatalf("左耳 = %d, want %d", got, want)
	}
	if got, want := sampleAt(out, 1), int16(150); got != want {
		t.Fatalf("右耳 = %d, want %d", got, want)
	}
}

func TestLoudSpeechIsCutAtTheLimitOnBothEars(t *testing.T) {
	h := &Handset{speakerChannels: 2, gain: 0.15, limit: 0.1}
	h.Play(pcm(32767, -32768))

	out := make([]byte, 8)
	h.fill(out, nil, 2)

	// 0.1 × 32768 = 3276.8 で、四捨五入すると 3277。符号は残す。
	for i, want := range []int16{3277, 3277, -3277, -3277} {
		if got := sampleAt(out, i); got != want {
			t.Fatalf("サンプル %d = %d, want %d", i, got, want)
		}
	}
}

func TestSpeechUnderTheLimitIsNotCut(t *testing.T) {
	h := &Handset{speakerChannels: 1, gain: 0.15, limit: 0.1}
	h.Play(pcm(-3000))

	out := make([]byte, 2)
	h.fill(out, nil, 1)

	if got, want := sampleAt(out, 0), int16(-450); got != want {
		t.Fatalf("音 = %d, want %d", got, want)
	}
}

func TestMacPlaybackCopiesTheSamplesUnchanged(t *testing.T) {
	h := &Handset{speakerChannels: 1}
	h.Play(pcm(1000, -2000))

	out := make([]byte, 4)
	h.fill(out, nil, 2)

	if got, want := sampleAt(out, 0), int16(1000); got != want {
		t.Fatalf("1 サンプル目 = %d, want %d", got, want)
	}
	if got, want := sampleAt(out, 1), int16(-2000); got != want {
		t.Fatalf("2 サンプル目 = %d, want %d", got, want)
	}
}

func TestHushDropsSpeechThatHasNotBeenPlayed(t *testing.T) {
	h := &Handset{speakerChannels: 1}
	h.Play(pcm(1000))
	h.Hush()

	out := make([]byte, 2)
	h.fill(out, nil, 1)
	if got := sampleAt(out, 0); got != 0 {
		t.Fatalf("捨てたあとの音 = %d, want 0", got)
	}
	if h.Playing() {
		t.Fatal("捨てたあとも再生中のまま")
	}
}

func TestCaptureKeepsTheConfiguredChannel(t *testing.T) {
	got := channel(pcm(10, 20, 30, 40), 2, 1)
	if sampleAt(got, 0) != 20 || sampleAt(got, 1) != 40 {
		t.Fatalf("右チャンネル = %d %d, want 20 40", sampleAt(got, 0), sampleAt(got, 1))
	}

	got = channel(pcm(10, 20, 30, 40), 2, 0)
	if sampleAt(got, 0) != 10 || sampleAt(got, 1) != 30 {
		t.Fatalf("左チャンネル = %d %d, want 10 30", sampleAt(got, 0), sampleAt(got, 1))
	}
}

func pcm(samples ...int16) []byte {
	buf := make([]byte, len(samples)*2)
	for i, s := range samples {
		binary.LittleEndian.PutUint16(buf[i*2:], uint16(s))
	}
	return buf
}

func sampleAt(buf []byte, i int) int16 {
	return int16(binary.LittleEndian.Uint16(buf[i*2:]))
}
