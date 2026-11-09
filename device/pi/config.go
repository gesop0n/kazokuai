package pi

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config は、電話機の受話器とフックと呼び出し音の設定である。環境変数が空なら既定を使う。
// 倍率の既定は 0.15 である。tel-base の 0.5 は、音全体を上限まで縮めるときの値で、
// こちらは倍率を掛けてから上限を超えた部分を切る。
type Config struct {
	AudioDevice      string
	MicChannel       int
	SpeakerGain      float64
	SpeakerLimit     float64
	GPIOChip         string
	HookGPIO         int
	RingerGPIO       int
	LiftedWhenClosed bool
	Debounce         time.Duration
}

// SettingsPath は、電話機の設定ファイルである。device check は、これがあれば読む。
const SettingsPath = "/etc/kazokuai/device.env"

// DefaultConfig は、この電話機の配線に合わせた既定である。
// 受話器を上げると接点が開く。tel-base の既定とは逆である。
func DefaultConfig() Config {
	return Config{
		MicChannel:       0,
		SpeakerGain:      0.15,
		SpeakerLimit:     0.1,
		GPIOChip:         "gpiochip0",
		HookGPIO:         5,
		RingerGPIO:       18,
		LiftedWhenClosed: false,
		Debounce:         50 * time.Millisecond,
	}
}

// ReadSettings は、device check が使う環境である。
// path の設定ファイルがあれば読み、getenv の空でない値で上書きする。
// ファイルが無いときは getenv だけを使う。読めないときは、既定に落とさない。
func ReadSettings(path string, getenv func(string) string) (func(string) string, error) {
	if getenv == nil {
		getenv = func(string) string { return "" }
	}
	file := map[string]string{}
	if path != "" {
		parsed, err := readEnvFile(path)
		if err != nil && !os.IsNotExist(err) {
			return nil, fmt.Errorf("設定ファイルを読めません: %w", err)
		}
		if err == nil {
			file = parsed
		}
	}
	return func(key string) string {
		if v := strings.TrimSpace(getenv(key)); v != "" {
			return v
		}
		return file[key]
	}, nil
}

// readEnvFile は、systemd の EnvironmentFile と同じく、空行と # か ; の行を読み飛ばす。
// 値が対の引用符で囲まれていれば、その引用符を外す。
func readEnvFile(path string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	values := map[string]string{}
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimSpace(strings.TrimRight(line, "\r"))
		if trimmed == "" || strings.HasPrefix(trimmed, "#") || strings.HasPrefix(trimmed, ";") {
			continue
		}
		key, value, ok := strings.Cut(trimmed, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		if len(value) >= 2 {
			q := value[0]
			if (q == '"' || q == '\'') && value[len(value)-1] == q {
				value = value[1 : len(value)-1]
			}
		}
		if key == "" {
			continue
		}
		values[key] = value
	}
	return values, nil
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
	if v := getenv("KAZOKUAI_RINGER_GPIO"); strings.TrimSpace(v) != "" {
		n, err := strconv.Atoi(strings.TrimSpace(v))
		if err != nil || n < 0 {
			return Config{}, fmt.Errorf("KAZOKUAI_RINGER_GPIO=%q は 0 以上の整数にしてください", v)
		}
		cfg.RingerGPIO = n
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
