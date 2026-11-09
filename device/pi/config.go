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
// path の設定ファイルがあれば読む。lookup にあれば、空でもその値を使う。
// 未設定の項目だけ、ファイルの値を使う。ファイルが無いときは lookup だけを使う。
// 読めないときは、既定に落とさない。
func ReadSettings(path string, lookup func(string) (string, bool)) (func(string) string, error) {
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
		if lookup != nil {
			if v, ok := lookup(key); ok {
				return strings.TrimSpace(v)
			}
		}
		return file[key]
	}, nil
}

// readEnvFile は、systemd の EnvironmentFile と同じ規則で読む。
// 空行、= の無い行、# か ; で始まる行は読み飛ばす。
// 引用符の外では、バックスラッシュが次の文字を残し、行末のバックスラッシュは次の行へ続く。
func readEnvFile(path string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return parseEnvFile(string(data)), nil
}

// systemd の src/basic/env-file.c と同じ状態である。
type envState int

const (
	envPreKey envState = iota
	envKey
	envPreValue
	envValue
	envValueEscape
	envSingle
	envDouble
	envDoubleEscape
	envComment
	envCommentEscape
)

func parseEnvFile(text string) map[string]string {
	values := map[string]string{}
	state := envPreKey
	var key, value []byte
	lastKeyWS := -1
	lastValueWS := -1

	push := func(st envState) {
		k := key
		if lastKeyWS >= 0 {
			k = k[:lastKeyWS]
		}
		v := value
		if st == envValue && lastValueWS >= 0 {
			v = v[:lastValueWS]
		}
		if len(k) > 0 {
			values[string(k)] = string(v)
		}
		key = key[:0]
		value = value[:0]
		lastKeyWS = -1
		lastValueWS = -1
	}

	for i := 0; i < len(text); i++ {
		c := text[i]
		switch state {
		case envPreKey:
			if c == '#' || c == ';' {
				state = envComment
			} else if !isEnvSpace(c) {
				state = envKey
				lastKeyWS = -1
				key = append(key, c)
			}
		case envKey:
			if isEnvBreak(c) {
				state = envPreKey
				key = key[:0]
				lastKeyWS = -1
			} else if c == '=' {
				state = envPreValue
				lastValueWS = -1
			} else {
				if !isEnvSpace(c) {
					lastKeyWS = -1
				} else if lastKeyWS < 0 {
					lastKeyWS = len(key)
				}
				key = append(key, c)
			}
		case envPreValue:
			switch {
			case isEnvBreak(c):
				push(state)
				state = envPreKey
			case c == '\'':
				state = envSingle
			case c == '"':
				state = envDouble
			case c == '\\':
				state = envValueEscape
			case !isEnvSpace(c):
				state = envValue
				value = append(value, c)
			}
		case envValue:
			switch {
			case isEnvBreak(c):
				push(state)
				state = envPreKey
			case c == '\\':
				state = envValueEscape
				lastValueWS = -1
			default:
				if !isEnvSpace(c) {
					lastValueWS = -1
				} else if lastValueWS < 0 {
					lastValueWS = len(value)
				}
				value = append(value, c)
			}
		case envValueEscape:
			state = envValue
			if !isEnvBreak(c) {
				value = append(value, c)
			}
		case envSingle:
			if c == '\'' {
				state = envPreValue
			} else {
				value = append(value, c)
			}
		case envDouble:
			switch c {
			case '"':
				state = envPreValue
			case '\\':
				state = envDoubleEscape
			default:
				value = append(value, c)
			}
		case envDoubleEscape:
			state = envDouble
			if isEnvShellEscape(c) {
				value = append(value, c)
			} else if !isEnvBreak(c) {
				value = append(value, '\\', c)
			}
		case envComment:
			switch {
			case c == '\\':
				state = envCommentEscape
			case isEnvBreak(c):
				state = envPreKey
			}
		case envCommentEscape:
			if isEnvBreak(c) {
				state = envPreKey
			} else {
				state = envComment
			}
		}
	}
	switch state {
	case envPreValue, envValue, envValueEscape, envSingle, envDouble, envDoubleEscape:
		push(state)
	}
	return values
}

func isEnvSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

func isEnvBreak(c byte) bool {
	return c == '\n' || c == '\r'
}

// isEnvShellEscape は、二重引用符の中でバックスラッシュが外れる文字である。
func isEnvShellEscape(c byte) bool {
	return c == '"' || c == '\\' || c == '`' || c == '$'
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
