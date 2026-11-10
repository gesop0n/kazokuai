// Package clip は、同期で受話器が話す言葉と、その WAV の読み書きである。
// 音声そのものは device/spoken がプログラムに埋め込む。
package clip

import (
	"encoding/binary"
	"errors"
	"fmt"
)

// SampleRate は、受話器が流す音声の速さ(Hz)である。16 ビット、モノラル。
const SampleRate = 24000

const (
	// IntroFile は、「認証コードは、」である。
	IntroFile = "intro.wav"
	// DesuFile は、「です。」である。
	DesuFile = "desu.wav"
	// AgainFile は、「もう一度お伝えします。」である。
	AgainFile = "again.wav"
	// CompletedFile は、同期が完了したときの文である。
	CompletedFile = "completed.wav"
	// OfflineFile は、インターネットにつながっていないときの文である。
	OfflineFile = "offline.wav"
	// FailedFile は、バックエンドがエラーを返したときの文である。
	FailedFile = "failed.wav"
)

// Clip は、1 つの音声である。
type Clip struct {
	// File は、clips ディレクトリの中の WAV の名前である。
	File string
	// Text は、読み上げる言葉である。
	Text string
}

// Clips は、0 から 9 の数字、認証コードの決まった言葉、3 つの文である。
// 数字は聞き間違えにくい読み方にする。
func Clips() []Clip {
	out := make([]Clip, len(clips))
	copy(out, clips)
	return out
}

// FileForDigit は、'0' から '9' の音声ファイルの名前を返す。
func FileForDigit(d byte) (string, bool) {
	if d < '0' || d > '9' {
		return "", false
	}
	return clips[d-'0'].File, true
}

var clips = []Clip{
	{File: "zero.wav", Text: "ゼロ"},
	{File: "ichi.wav", Text: "いち"},
	{File: "ni.wav", Text: "に"},
	{File: "san.wav", Text: "さん"},
	{File: "yon.wav", Text: "よん"},
	{File: "go.wav", Text: "ご"},
	{File: "roku.wav", Text: "ろく"},
	{File: "nana.wav", Text: "なな"},
	{File: "hachi.wav", Text: "はち"},
	{File: "kyu.wav", Text: "きゅう"},
	{File: IntroFile, Text: "認証コードは、"},
	{File: DesuFile, Text: "です。"},
	{File: AgainFile, Text: "もう一度お伝えします。"},
	{File: CompletedFile, Text: "同期が完了しました。受話器を置いてください。"},
	{File: OfflineFile, Text: "インターネットにつながっていません。Wi-Fi を確かめてください。"},
	{File: FailedFile, Text: "うまくいきませんでした。しばらくしてから、もう一度シャープを押してください。"},
}

// PCM は、受話器が流せる WAV から PCM を取り出す。
// 24 kHz、16 ビット、モノラル、リトルエンディアンで、空でないものだけを受け付ける。
func PCM(wav []byte) ([]byte, error) {
	if len(wav) < 12 || string(wav[0:4]) != "RIFF" || string(wav[8:12]) != "WAVE" {
		return nil, errors.New("WAV ではありません")
	}
	var fmtChunk, data []byte
	rest := wav[12:]
	for len(rest) >= 8 {
		id := string(rest[0:4])
		size := int(binary.LittleEndian.Uint32(rest[4:8]))
		rest = rest[8:]
		if size > len(rest) {
			return nil, errors.New("WAV の長さが合いません")
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
	if err := checkFormat(fmtChunk); err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return nil, errors.New("音声が空です")
	}
	if len(data)%2 != 0 {
		return nil, errors.New("音声の長さがサンプルと合いません")
	}
	return append([]byte(nil), data...), nil
}

func checkFormat(chunk []byte) error {
	if len(chunk) < 16 {
		return errors.New("WAV の形式がありません")
	}
	format := binary.LittleEndian.Uint16(chunk[0:2])
	channels := binary.LittleEndian.Uint16(chunk[2:4])
	rate := binary.LittleEndian.Uint32(chunk[4:8])
	bits := binary.LittleEndian.Uint16(chunk[14:16])
	if format != 1 || channels != 1 || rate != SampleRate || bits != 16 {
		return fmt.Errorf("音声の形式が違います: format=%d channels=%d rate=%d bits=%d", format, channels, rate, bits)
	}
	return nil
}

// WAV は、PCM を受話器と同じ形式の WAV にする。
func WAV(pcm []byte) []byte {
	header := make([]byte, 44)
	copy(header[0:4], "RIFF")
	binary.LittleEndian.PutUint32(header[4:8], uint32(36+len(pcm)))
	copy(header[8:12], "WAVE")
	copy(header[12:16], "fmt ")
	binary.LittleEndian.PutUint32(header[16:20], 16)
	binary.LittleEndian.PutUint16(header[20:22], 1)
	binary.LittleEndian.PutUint16(header[22:24], 1)
	binary.LittleEndian.PutUint32(header[24:28], SampleRate)
	binary.LittleEndian.PutUint32(header[28:32], SampleRate*2)
	binary.LittleEndian.PutUint16(header[32:34], 2)
	binary.LittleEndian.PutUint16(header[34:36], 16)
	copy(header[36:40], "data")
	binary.LittleEndian.PutUint32(header[40:44], uint32(len(pcm)))
	return append(header, pcm...)
}
