package pi

import (
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
	if cfg.GPIOChip != "gpiochip0" || cfg.HookGPIO != 5 || !cfg.LiftedWhenClosed {
		t.Fatalf("フック = %s GPIO%d 閉じると上がる=%v", cfg.GPIOChip, cfg.HookGPIO, cfg.LiftedWhenClosed)
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
		"KAZOKUAI_LIFTED_WHEN_CLOSED": "false",
		"KAZOKUAI_HOOK_DEBOUNCE":      "20ms",
	}
	cfg, err := Load(func(key string) string { return env[key] })
	if err != nil {
		t.Fatal(err)
	}
	if cfg.AudioDevice != "USB Audio" || cfg.MicChannel != 1 || cfg.SpeakerGain != 0.2 || cfg.SpeakerLimit != 0.05 {
		t.Fatalf("音声 = %+v", cfg)
	}
	if cfg.GPIOChip != "gpiochip4" || cfg.HookGPIO != 6 || cfg.LiftedWhenClosed || cfg.Debounce != 20*time.Millisecond {
		t.Fatalf("フック = %+v", cfg)
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
