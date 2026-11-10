package spoken_test

import (
	"bytes"
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/device/spoken"
	"github.com/gesop0n/kazokuai/device/spoken/clip"
)

func TestCodeSpeaksTheDigitsTwiceWithAPauseBetweenThem(t *testing.T) {
	const digits = "482751" // 仕様書の例
	got, err := spoken.Code(digits)
	if err != nil {
		t.Fatal(err)
	}
	once := digitsWithPauses(t, digits)
	want := concat(
		readClipPCM(t, clip.IntroFile),
		once,
		readClipPCM(t, clip.DesuFile),
		readClipPCM(t, clip.AgainFile),
		once,
		readClipPCM(t, clip.DesuFile),
	)
	if !bytes.Equal(got, want) {
		t.Fatalf("認証コードの音声が違う: got %d バイト, want %d バイト", len(got), len(want))
	}
}

func TestSentencesAreTheCommittedClips(t *testing.T) {
	checks := []struct {
		file string
		got  []byte
	}{
		{clip.CompletedFile, spoken.Completed()},
		{clip.OfflineFile, spoken.Offline()},
		{clip.FailedFile, spoken.Failed()},
	}
	for _, c := range checks {
		want := readClipPCM(t, c.file)
		if !bytes.Equal(c.got, want) {
			t.Fatalf("%s の音声がファイルと違う", c.file)
		}
	}
}

func TestCodeRejectsAnythingButSixDigits(t *testing.T) {
	for _, digits := range []string{"", "12345", "1234567", "48275a", "４８２７５１"} {
		if _, err := spoken.Code(digits); err == nil {
			t.Fatalf("Code(%q) がエラーを返さなかった", digits)
		}
	}
}

func TestEveryClipIsANonEmptyHandsetWav(t *testing.T) {
	if spoken.SampleRate != 24000 {
		t.Fatalf("速さ = %d, want 24000", spoken.SampleRate)
	}
	if spoken.SampleRate != phone.SpeakerSampleRate {
		t.Fatalf("速さ = %d, 受話器は %d", spoken.SampleRate, phone.SpeakerSampleRate)
	}
	want := map[string]bool{}
	for _, c := range clip.Clips() {
		want[c.File] = true
	}
	entries, err := os.ReadDir("clips")
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != len(want) {
		t.Fatalf("clips に %d 個、want %d 個", len(entries), len(want))
	}
	for _, entry := range entries {
		if !want[entry.Name()] {
			t.Fatalf("想定していないファイル %s", entry.Name())
		}
		checkHandsetWAV(t, filepath.Join("clips", entry.Name()))
	}
}

// digitsWithPauses は、6 桁のあいだにだけ 400 ミリ秒の無音を置いた PCM である。
// 仕様の「短い間」は、この 400 ミリ秒とする。
func digitsWithPauses(t *testing.T, digits string) []byte {
	t.Helper()
	pause := make([]byte, silenceBytes(400*time.Millisecond))
	parts := make([][]byte, 0, len(digits)*2-1)
	for i := 0; i < len(digits); i++ {
		if i > 0 {
			parts = append(parts, pause)
		}
		file, ok := clip.FileForDigit(digits[i])
		if !ok {
			t.Fatalf("数字ではない: %q", digits[i:i+1])
		}
		parts = append(parts, readClipPCM(t, file))
	}
	return concat(parts...)
}

func silenceBytes(d time.Duration) int {
	samples := int(d) * spoken.SampleRate / int(time.Second)
	return samples * 2
}

func readClipPCM(t *testing.T, name string) []byte {
	t.Helper()
	wav, err := os.ReadFile(filepath.Join("clips", name))
	if err != nil {
		t.Fatal(err)
	}
	pcm, err := pcmOf(wav)
	if err != nil {
		t.Fatal(err)
	}
	return pcm
}

func checkHandsetWAV(t *testing.T, path string) {
	t.Helper()
	wav, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	pcm, err := pcmOf(wav)
	if err != nil {
		t.Fatalf("%s: %v", path, err)
	}
	if len(pcm) == 0 {
		t.Fatalf("%s が空です", path)
	}
}

// pcmOf は、テストが自分で WAV を読む。実装の読み方とは別に書く。
func pcmOf(wav []byte) ([]byte, error) {
	if len(wav) < 12 || string(wav[0:4]) != "RIFF" || string(wav[8:12]) != "WAVE" {
		return nil, errFormat("WAV ではありません")
	}
	var fmtChunk, data []byte
	rest := wav[12:]
	for len(rest) >= 8 {
		id := string(rest[0:4])
		size := int(binary.LittleEndian.Uint32(rest[4:8]))
		rest = rest[8:]
		if size > len(rest) {
			return nil, errFormat("WAV の長さが合いません")
		}
		chunk := rest[:size]
		rest = rest[size:]
		if size%2 == 1 && len(rest) > 0 {
			rest = rest[1:]
		}
		switch id {
		case "fmt ":
			fmtChunk = chunk
		case "data":
			data = chunk
		}
	}
	if len(fmtChunk) < 16 {
		return nil, errFormat("WAV の形式がありません")
	}
	format := binary.LittleEndian.Uint16(fmtChunk[0:2])
	channels := binary.LittleEndian.Uint16(fmtChunk[2:4])
	rate := binary.LittleEndian.Uint32(fmtChunk[4:8])
	bits := binary.LittleEndian.Uint16(fmtChunk[14:16])
	if format != 1 || channels != 1 || rate != 24000 || bits != 16 {
		return nil, errFormat("形式が違います")
	}
	if len(data) == 0 || len(data)%2 != 0 {
		return nil, errFormat("音声が空か、サンプルが欠けています")
	}
	return append([]byte(nil), data...), nil
}

type errFormat string

func (e errFormat) Error() string { return string(e) }

func concat(parts ...[]byte) []byte {
	n := 0
	for _, p := range parts {
		n += len(p)
	}
	out := make([]byte, 0, n)
	for _, p := range parts {
		out = append(out, p...)
	}
	return out
}
