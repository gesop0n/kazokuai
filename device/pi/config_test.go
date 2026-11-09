package pi

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDefaultConfigMatchesTheHandsetWiring(t *testing.T) {
	cfg, err := Load(func(string) string { return "" })
	if err != nil {
		t.Fatal(err)
	}
	if cfg.AudioDevice != "" || cfg.MicChannel != 0 {
		t.Fatalf("音声 = %q チャンネル %d", cfg.AudioDevice, cfg.MicChannel)
	}
	if cfg.SpeakerGain != 0.15 || cfg.SpeakerLimit != 0.1 {
		t.Fatalf("音量 = %v 上限 %v, want 0.15 と 0.1", cfg.SpeakerGain, cfg.SpeakerLimit)
	}
	if cfg.GPIOChip != "gpiochip0" || cfg.HookGPIO != 5 || cfg.RingerGPIO != 18 || cfg.LiftedWhenClosed {
		t.Fatalf("GPIO = %s フック %d 呼び出し音 %d 閉じると上がる=%v", cfg.GPIOChip, cfg.HookGPIO, cfg.RingerGPIO, cfg.LiftedWhenClosed)
	}
	if cfg.Debounce != 50*time.Millisecond {
		t.Fatalf("デバウンス = %s, want 50ms", cfg.Debounce)
	}
}

func TestConfigReadsTheEnvironment(t *testing.T) {
	env := map[string]string{
		"KAZOKUAI_AUDIO_DEVICE":       "USB Audio",
		"KAZOKUAI_MIC_CHANNEL":        "1",
		"KAZOKUAI_SPEAKER_GAIN":       "0.2",
		"KAZOKUAI_SPEAKER_LIMIT":      "0.05",
		"KAZOKUAI_GPIO_CHIP":          "gpiochip4",
		"KAZOKUAI_HOOK_GPIO":          "6",
		"KAZOKUAI_RINGER_GPIO":        "12",
		"KAZOKUAI_LIFTED_WHEN_CLOSED": "true",
		"KAZOKUAI_HOOK_DEBOUNCE":      "20ms",
	}
	cfg, err := Load(func(key string) string { return env[key] })
	if err != nil {
		t.Fatal(err)
	}
	if cfg.AudioDevice != "USB Audio" || cfg.MicChannel != 1 || cfg.SpeakerGain != 0.2 || cfg.SpeakerLimit != 0.05 {
		t.Fatalf("音声 = %+v", cfg)
	}
	if cfg.GPIOChip != "gpiochip4" || cfg.HookGPIO != 6 || cfg.RingerGPIO != 12 || !cfg.LiftedWhenClosed || cfg.Debounce != 20*time.Millisecond {
		t.Fatalf("フック = %+v", cfg)
	}
}

func TestDeviceCheckReadsTheSettingsFileAndTheEnvironmentWins(t *testing.T) {
	if SettingsPath != "/etc/kazokuai/device.env" {
		t.Fatalf("設定ファイル = %s", SettingsPath)
	}
	path := filepath.Join(t.TempDir(), "device.env")
	body := "" +
		"# コメントは読み飛ばす\n" +
		"KAZOKUAI_AUDIO_DEVICE=\"Unitek\"\n" +
		"KAZOKUAI_HOOK_GPIO=9\n" +
		"KAZOKUAI_LIFTED_WHEN_CLOSED=true\n"
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}

	fileOnly, err := ReadSettings(path, func(string) string { return "" })
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := Load(fileOnly)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.AudioDevice != "Unitek" || cfg.HookGPIO != 9 || !cfg.LiftedWhenClosed {
		t.Fatalf("ファイル = 機器 %q フック %d 閉じると上がる %v", cfg.AudioDevice, cfg.HookGPIO, cfg.LiftedWhenClosed)
	}

	overridden, err := ReadSettings(path, func(key string) string {
		if key == "KAZOKUAI_AUDIO_DEVICE" {
			return "Handset"
		}
		return ""
	})
	if err != nil {
		t.Fatal(err)
	}
	cfg, err = Load(overridden)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.AudioDevice != "Handset" || cfg.HookGPIO != 9 || !cfg.LiftedWhenClosed {
		t.Fatalf("上書き = 機器 %q フック %d 閉じると上がる %v", cfg.AudioDevice, cfg.HookGPIO, cfg.LiftedWhenClosed)
	}
}

func TestDeviceCheckUsesDefaultsWhenTheSettingsFileIsMissing(t *testing.T) {
	getenv, err := ReadSettings(filepath.Join(t.TempDir(), "missing.env"), func(string) string { return "" })
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := Load(getenv)
	if err != nil {
		t.Fatal(err)
	}
	want := DefaultConfig()
	if cfg != want {
		t.Fatalf("無いファイル = %+v, want %+v", cfg, want)
	}
}

func TestDeviceCheckReportsAnUnreadableSettingsFile(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root は許可を無視する")
	}
	path := filepath.Join(t.TempDir(), "device.env")
	if err := os.WriteFile(path, []byte("KAZOKUAI_AUDIO_DEVICE=Unitek\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(path, 0o600) })
	if _, err := ReadSettings(path, func(string) string { return "" }); err == nil {
		t.Fatal("読めない設定ファイルを、無いものとして扱った")
	}
}

func TestConfigRejectsABadVolume(t *testing.T) {
	_, err := Load(func(key string) string {
		if key == "KAZOKUAI_SPEAKER_GAIN" {
			return "5"
		}
		return ""
	})
	if err == nil || !strings.Contains(err.Error(), "KAZOKUAI_SPEAKER_GAIN") {
		t.Fatalf("倍率 = %v", err)
	}

	_, err = Load(func(key string) string {
		if key == "KAZOKUAI_SPEAKER_LIMIT" {
			return "0"
		}
		return ""
	})
	if err == nil || !strings.Contains(err.Error(), "KAZOKUAI_SPEAKER_LIMIT") {
		t.Fatalf("上限 = %v", err)
	}
}

func TestConfigRejectsABadRingerPin(t *testing.T) {
	_, err := Load(func(key string) string {
		if key == "KAZOKUAI_RINGER_GPIO" {
			return "gpio18"
		}
		return ""
	})
	if err == nil || !strings.Contains(err.Error(), "KAZOKUAI_RINGER_GPIO") {
		t.Fatalf("呼び出し音の GPIO = %v", err)
	}
}
