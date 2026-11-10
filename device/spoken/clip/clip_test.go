package clip_test

import (
	"bytes"
	"encoding/binary"
	"testing"

	"github.com/gesop0n/kazokuai/device/spoken/clip"
)

func TestClipsAreTheDigitsPhrasesAndSentences(t *testing.T) {
	got := map[string]string{}
	for _, c := range clip.Clips() {
		if _, ok := got[c.File]; ok {
			t.Fatalf("ファイル %s が重なっています", c.File)
		}
		got[c.File] = c.Text
	}
	want := map[string]string{
		"zero.wav":      "ゼロ",
		"ichi.wav":      "いち",
		"ni.wav":        "に",
		"san.wav":       "さん",
		"yon.wav":       "よん",
		"go.wav":        "ご",
		"roku.wav":      "ろく",
		"nana.wav":      "なな",
		"hachi.wav":     "はち",
		"kyu.wav":       "きゅう",
		"intro.wav":     "認証コードは、",
		"desu.wav":      "です。",
		"again.wav":     "もう一度お伝えします。",
		"completed.wav": "同期が完了しました。受話器を置いてください。",
		"offline.wav":   "インターネットにつながっていません。Wi-Fi を確かめてください。",
		"failed.wav":    "うまくいきませんでした。しばらくしてから、もう一度シャープを押してください。",
	}
	if len(got) != len(want) {
		t.Fatalf("音声が %d 個、want %d 個", len(got), len(want))
	}
	for file, text := range want {
		if got[file] != text {
			t.Fatalf("%s の言葉 = %q, want %q", file, got[file], text)
		}
	}
}

func TestDigitFilesFollowTheReading(t *testing.T) {
	want := []string{
		"zero.wav", "ichi.wav", "ni.wav", "san.wav", "yon.wav",
		"go.wav", "roku.wav", "nana.wav", "hachi.wav", "kyu.wav",
	}
	for d := byte('0'); d <= '9'; d++ {
		file, ok := clip.FileForDigit(d)
		if !ok {
			t.Fatalf("%c のファイルがない", d)
		}
		if file != want[d-'0'] {
			t.Fatalf("%c のファイル = %s, want %s", d, file, want[d-'0'])
		}
	}
	if _, ok := clip.FileForDigit('a'); ok {
		t.Fatal("数字でない文字にファイルがあった")
	}
}

func TestPCMReadsHandsetAudio(t *testing.T) {
	pcm := []byte{0x34, 0x12, 0x00, 0x80}
	got, err := clip.PCM(wavOf(24000, 1, 16, pcm))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, pcm) {
		t.Fatalf("PCM = %v, want %v", got, pcm)
	}
}

func TestWAVRoundTripsHandsetAudio(t *testing.T) {
	pcm := []byte{0x01, 0x00, 0xfe, 0xff}
	got, err := clip.PCM(clip.WAV(pcm))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, pcm) {
		t.Fatalf("PCM = %v, want %v", got, pcm)
	}
}

func TestPCMRejectsAudioTheHandsetCannotPlay(t *testing.T) {
	pcm := []byte{0x01, 0x00, 0x02, 0x00}
	cases := []struct {
		name string
		wav  []byte
	}{
		{name: "WAV ではない", wav: []byte("hello")},
		{name: "16 kHz", wav: wavOf(16000, 1, 16, pcm)},
		{name: "ステレオ", wav: wavOf(24000, 2, 16, pcm)},
		{name: "8 ビット", wav: wavOf(24000, 1, 8, pcm)},
		{name: "空", wav: wavOf(24000, 1, 16, nil)},
		{name: "サンプルが欠けている", wav: wavOf(24000, 1, 16, []byte{0x01})},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := clip.PCM(tc.wav); err == nil {
				t.Fatal("エラーを返さなかった")
			}
		})
	}
}

// wavOf は、テストが自分で作る WAV である。実装の WAV とは別に書く。
func wavOf(rate, channels, bits int, pcm []byte) []byte {
	block := channels * bits / 8
	header := make([]byte, 44)
	copy(header[0:4], "RIFF")
	binary.LittleEndian.PutUint32(header[4:8], uint32(36+len(pcm)))
	copy(header[8:12], "WAVE")
	copy(header[12:16], "fmt ")
	binary.LittleEndian.PutUint32(header[16:20], 16)
	binary.LittleEndian.PutUint16(header[20:22], 1)
	binary.LittleEndian.PutUint16(header[22:24], uint16(channels))
	binary.LittleEndian.PutUint32(header[24:28], uint32(rate))
	binary.LittleEndian.PutUint32(header[28:32], uint32(rate*block))
	binary.LittleEndian.PutUint16(header[32:34], uint16(block))
	binary.LittleEndian.PutUint16(header[34:36], uint16(bits))
	copy(header[36:40], "data")
	binary.LittleEndian.PutUint32(header[40:44], uint32(len(pcm)))
	return append(header, pcm...)
}
