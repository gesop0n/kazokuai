package handset

import (
	"strings"
	"testing"
)

func TestChoosePicksTheNamedAdapter(t *testing.T) {
	names := []string{"Built-in", "USB Audio Device", "HDMI"}

	got, err := choose(names, "USB Audio Device")
	if err != nil || names[got] != "USB Audio Device" {
		t.Fatalf("完全一致 = %q, %v", names[got], err)
	}

	got, err = choose(names, "USB")
	if err != nil || names[got] != "USB Audio Device" {
		t.Fatalf("部分一致 = %q, %v", names[got], err)
	}
}

func TestChooseRejectsAMissingOrAmbiguousName(t *testing.T) {
	names := []string{"USB Audio", "USB Headset"}

	if _, err := choose(names, "Bluetooth"); err == nil || !strings.Contains(err.Error(), "Bluetooth") {
		t.Fatalf("無い機器 = %v", err)
	}
	err := errorFrom(choose(names, "USB"))
	if err == nil || !strings.Contains(err.Error(), "USB Audio") || !strings.Contains(err.Error(), "USB Headset") {
		t.Fatalf("曖昧 = %v", err)
	}
	if _, err := choose(names, "  "); err == nil || !strings.Contains(err.Error(), "KAZOKUAI_AUDIO_DEVICE") {
		t.Fatalf("空 = %v", err)
	}
}

// Raspberry Pi の PipeWire が並べた名前である。録音には、再生の音を写すモニターも並ぶ。
func TestChooseCaptureSkipsMonitors(t *testing.T) {
	playback := []string{"Audio Adapter (Unitek Y-247A) Analog Stereo", "Built-in Audio Stereo"}
	capture := []string{
		"Monitor of Audio Adapter (Unitek Y-247A) Analog Stereo",
		"Audio Adapter (Unitek Y-247A) Mono",
		"Monitor of Built-in Audio Stereo",
	}

	out, err := choose(playback, "Unitek")
	if err != nil || playback[out] != "Audio Adapter (Unitek Y-247A) Analog Stereo" {
		t.Fatalf("再生 = %q, %v", playback[out], err)
	}
	in, err := chooseCapture(capture, "Unitek")
	if err != nil || capture[in] != "Audio Adapter (Unitek Y-247A) Mono" {
		t.Fatalf("録音 = %q, %v", capture[in], err)
	}

	// 再生の機器の名前をそのまま渡しても、モニターは選ばない
	if _, err := chooseCapture(capture, "Audio Adapter (Unitek Y-247A) Analog Stereo"); err == nil {
		t.Fatal("モニターを選んだ")
	}
}

func TestFormatDevicesListsPlaybackAndCapture(t *testing.T) {
	got := FormatDevices(
		[]Device{{Name: "USB Audio", Channels: 2}},
		[]Device{{Name: "USB Audio", Channels: 1}},
	)
	want := "再生:\n  USB Audio (2 チャンネル)\n録音:\n  USB Audio (1 チャンネル)\n"
	if got != want {
		t.Fatalf("一覧 =\n%s\nwant\n%s", got, want)
	}

	got = FormatDevices(nil, nil)
	if !strings.Contains(got, "再生:\n  (なし)\n") || !strings.Contains(got, "録音:\n  (なし)\n") {
		t.Fatalf("空の一覧 =\n%s", got)
	}
}

func errorFrom(_ int, err error) error { return err }
