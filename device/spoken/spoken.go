// Package spoken は、同期のときに受話器が話す音声を返す。
// 音声は Gemini の音声合成で 1 回作り、このパッケージに埋め込んである。
// 受話器へ流すのは、認証コードを読み上げる側である。
package spoken

import (
	"embed"
	"errors"
	"fmt"
	"time"

	"github.com/gesop0n/kazokuai/device/spoken/clip"
)

//go:embed clips/*.wav
var files embed.FS

// SampleRate は、受話器が流す音声の速さ(Hz)である。16 ビット、モノラル、リトルエンディアン。
const SampleRate = clip.SampleRate

// digitPause は、認証コードの数字と数字のあいだの無音である。
// 仕様の「短い間」は 400 ミリ秒とする。
const digitPause = 400 * time.Millisecond

func init() {
	cache = make(map[string][]byte, len(clip.Clips()))
	for _, c := range clip.Clips() {
		wav, err := files.ReadFile("clips/" + c.File)
		if err != nil {
			panic(err)
		}
		pcm, err := clip.PCM(wav)
		if err != nil {
			panic(fmt.Errorf("%s: %w", c.File, err))
		}
		cache[c.File] = pcm
	}
}

var cache map[string][]byte

// Code は、6 桁の認証コードを受話器が話す PCM を返す。
// 並びは「認証コードは、」、あいだに短い間を置いた 6 つの数字、「です。」、
// 「もう一度お伝えします。」、もう一度 6 つの数字、「です。」である。
func Code(digits string) ([]byte, error) {
	if len(digits) != 6 {
		return nil, errors.New("認証コードは 6 桁です")
	}
	once, err := digitAudio(digits)
	if err != nil {
		return nil, err
	}
	parts := make([][]byte, 0, 4+len(once)*2)
	parts = append(parts, cache[clip.IntroFile])
	parts = append(parts, once...)
	parts = append(parts, cache[clip.DesuFile], cache[clip.AgainFile])
	parts = append(parts, once...)
	parts = append(parts, cache[clip.DesuFile])
	return concat(parts), nil
}

// Completed は、「同期が完了しました。受話器を置いてください。」の PCM を返す。
func Completed() []byte { return append([]byte(nil), cache[clip.CompletedFile]...) }

// Offline は、「インターネットにつながっていません。Wi-Fi を確かめてください。」の PCM を返す。
func Offline() []byte { return append([]byte(nil), cache[clip.OfflineFile]...) }

// Failed は、「うまくいきませんでした。しばらくしてから、もう一度シャープを押してください。」の PCM を返す。
func Failed() []byte { return append([]byte(nil), cache[clip.FailedFile]...) }

func digitAudio(digits string) ([][]byte, error) {
	pause := silence(digitPause)
	out := make([][]byte, 0, len(digits)*2-1)
	for i := 0; i < len(digits); i++ {
		file, ok := clip.FileForDigit(digits[i])
		if !ok {
			return nil, fmt.Errorf("認証コードの %q は数字ではありません", digits[i:i+1])
		}
		if i > 0 {
			out = append(out, pause)
		}
		out = append(out, cache[file])
	}
	return out, nil
}

func silence(d time.Duration) []byte {
	samples := int(d) * SampleRate / int(time.Second)
	return make([]byte, samples*2)
}

func concat(parts [][]byte) []byte {
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
