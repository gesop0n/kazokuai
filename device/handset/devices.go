package handset

import (
	"errors"
	"fmt"
	"strings"

	"github.com/gen2brain/malgo"
)

// Device は、一覧に出す音声の機器である。
type Device struct {
	Name     string
	Channels int
	id       malgo.DeviceID
}

// Devices は、再生と録音の機器を名前で並べる。音は出さない。
func Devices() (playback, capture []Device, err error) {
	ctx, err := malgo.InitContext(nil, malgo.ContextConfig{}, nil)
	if err != nil {
		return nil, nil, fmt.Errorf("音声を使えなかった: %w", err)
	}
	defer func() {
		ctx.Uninit()
		ctx.Free()
	}()
	playback, err = list(ctx, malgo.Playback)
	if err != nil {
		return nil, nil, err
	}
	capture, err = list(ctx, malgo.Capture)
	if err != nil {
		return nil, nil, err
	}
	return playback, capture, nil
}

// FormatDevices は、配線する人が読む機器の一覧である。
func FormatDevices(playback, capture []Device) string {
	var b strings.Builder
	write := func(title string, devices []Device) {
		fmt.Fprintf(&b, "%s:\n", title)
		if len(devices) == 0 {
			fmt.Fprintf(&b, "  (なし)\n")
			return
		}
		for _, d := range devices {
			if d.Channels > 0 {
				fmt.Fprintf(&b, "  %s (%d チャンネル)\n", d.Name, d.Channels)
			} else {
				fmt.Fprintf(&b, "  %s\n", d.Name)
			}
		}
	}
	write("再生", playback)
	write("録音", capture)
	return b.String()
}

func list(ctx *malgo.AllocatedContext, kind malgo.DeviceType) ([]Device, error) {
	infos, err := ctx.Devices(kind)
	if err != nil {
		return nil, fmt.Errorf("音声の機器を読めなかった: %w", err)
	}
	out := make([]Device, len(infos))
	for i, info := range infos {
		channels := maxChannels(info)
		if channels == 0 {
			full, err := ctx.DeviceInfo(kind, info.ID, malgo.Shared)
			if err == nil {
				channels = maxChannels(full)
			}
		}
		out[i] = Device{Name: info.Name(), Channels: channels, id: info.ID}
	}
	return out, nil
}

func names(devices []Device) []string {
	out := make([]string, len(devices))
	for i, d := range devices {
		out[i] = d.Name
	}
	return out
}

// choose は、want に一致する機器を 1 つ選ぶ。完全一致を先に使い、無ければ名前に含まれるものを使う。
func choose(deviceNames []string, want string) (int, error) {
	if strings.TrimSpace(want) == "" {
		return 0, errors.New("音声の機器の名前が要ります。KAZOKUAI_AUDIO_DEVICE に、機器名の一部を入れてください")
	}
	found := match(deviceNames, func(name string) bool { return name == want })
	if len(found) == 0 {
		found = match(deviceNames, func(name string) bool { return strings.Contains(name, want) })
	}
	switch len(found) {
	case 1:
		return found[0], nil
	case 0:
		return 0, fmt.Errorf("音声の機器に %q がありません", want)
	default:
		var b strings.Builder
		fmt.Fprintf(&b, "音声の機器 %q が %d 個あります。名前を長くしてください:", want, len(found))
		for _, i := range found {
			fmt.Fprintf(&b, "\n  %s", deviceNames[i])
		}
		return 0, errors.New(b.String())
	}
}

// monitorPrefix は、PipeWire や PulseAudio が再生の音をそのまま録るために作る入力の名前の頭である。マイクではない。
const monitorPrefix = "Monitor of "

// chooseCapture は、録音の機器から want に一致するマイクを 1 つ選ぶ。モニターは外すので、
// 「Unitek」のような 1 つの名前で、再生の機器とマイクの両方を選べる。
func chooseCapture(deviceNames []string, want string) (int, error) {
	var mics []string
	var index []int
	for i, name := range deviceNames {
		if strings.HasPrefix(name, monitorPrefix) {
			continue
		}
		mics = append(mics, name)
		index = append(index, i)
	}
	got, err := choose(mics, want)
	if err != nil {
		return 0, err
	}
	return index[got], nil
}

func match(deviceNames []string, ok func(string) bool) []int {
	var found []int
	for i, name := range deviceNames {
		if ok(name) {
			found = append(found, i)
		}
	}
	return found
}

func maxChannels(info malgo.DeviceInfo) int {
	n := 0
	for _, format := range info.Formats {
		if int(format.Channels) > n {
			n = int(format.Channels)
		}
	}
	return n
}

// atMostTwo は、スピーカーとマイクを開くチャンネル数である。2 以上なら 2、1 なら 1、不明なら 2 を試す。
func atMostTwo(channels int) int {
	if channels == 1 {
		return 1
	}
	return 2
}
