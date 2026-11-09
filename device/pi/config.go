package pi

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Config は、電話機の受話器とフックの設定である。環境変数が空なら既定を使う。
// 倍率の既定は 0.15 である。tel-base の 0.5 は、音全体を上限まで縮めるときの値で、
// こちらは倍率を掛けてから上限を超えた部分を切る。
type Config struct {
	AudioDevice      string
	MicChannel       int
	SpeakerGain      float64
	SpeakerLimit     float64
	GPIOChip         string
	HookGPIO         int
	LiftedWhenClosed bool
	Debounce         time.Duration
}

// DefaultConfig は、Raspberry Pi 4 の受話器の配線に合わせた既定である。
func DefaultConfig() Config {
	return Config{
		MicChannel:       0,
		SpeakerGain:      0.15,
		SpeakerLimit:     0.1,
		GPIOChip:         "gpiochip0",
		HookGPIO:         5,
		LiftedWhenClosed: true,
		Debounce:         50 * time.Millisecond,
	}
}

// Load は、環境変数で上書きした設定を返す。空の変数は既定のままにする。
func Load(getenv func(string) string) (Config, error) {
	cfg := DefaultConfig()
	if v := strings.TrimSpace(getenv("KAZOKUAI_AUDIO_DEVICE")); v != "" {
		cfg.AudioDevice = v
	}
	if v := getenv("KAZOKUAI_MIC_CHANNEL"); strings.TrimSpace(v) != "" {
		n, err := strconv.Atoi(strings.TrimSpace(v))
		if err != nil || n < 0 {
			return Config{}, fmt.Errorf("KAZOKUAI_MIC_CHANNEL=%q は 0 以上の整数にしてください", v)
		}
		cfg.MicChannel = n
	}
	if v := getenv("KAZOKUAI_SPEAKER_GAIN"); strings.TrimSpace(v) != "" {
		n, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
		if err != nil || n <= 0 || n > 4 {
			return Config{}, fmt.Errorf("KAZOKUAI_SPEAKER_GAIN=%q は 0 より大きく 4 以下にしてください", v)
		}
		cfg.SpeakerGain = n
	}
	if v := getenv("KAZOKUAI_SPEAKER_LIMIT"); strings.TrimSpace(v) != "" {
		n, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
		if err != nil || n <= 0 || n > 1 {
			return Config{}, fmt.Errorf("KAZOKUAI_SPEAKER_LIMIT=%q は 0 より大きく 1 以下にしてください", v)
		}
		cfg.SpeakerLimit = n
	}
	if v := strings.TrimSpace(getenv("KAZOKUAI_GPIO_CHIP")); v != "" {
		cfg.GPIOChip = v
	}
	if v := getenv("KAZOKUAI_HOOK_GPIO"); strings.TrimSpace(v) != "" {
		n, err := strconv.Atoi(strings.TrimSpace(v))
		if err != nil || n < 0 {
			return Config{}, fmt.Errorf("KAZOKUAI_HOOK_GPIO=%q は 0 以上の整数にしてください", v)
		}
		cfg.HookGPIO = n
	}
	if v := getenv("KAZOKUAI_LIFTED_WHEN_CLOSED"); strings.TrimSpace(v) != "" {
		on, err := strconv.ParseBool(strings.TrimSpace(v))
		if err != nil {
			return Config{}, fmt.Errorf("KAZOKUAI_LIFTED_WHEN_CLOSED=%q は true か false にしてください", v)
		}
		cfg.LiftedWhenClosed = on
	}
	if v := getenv("KAZOKUAI_HOOK_DEBOUNCE"); strings.TrimSpace(v) != "" {
		d, err := time.ParseDuration(strings.TrimSpace(v))
		if err != nil || d <= 0 {
			return Config{}, fmt.Errorf("KAZOKUAI_HOOK_DEBOUNCE=%q は 50ms のような長さにしてください", v)
		}
		cfg.Debounce = d
	}
	return cfg, nil
}
