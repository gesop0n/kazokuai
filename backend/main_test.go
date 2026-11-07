package main

import (
	"flag"
	"strings"
	"testing"
	"time"

	"github.com/gesop0n/kazokuai/backend/server"
)

func TestTimeFlags(t *testing.T) {
	t.Run("既定値は、呼び出しの上限 1 分、電話の長さの上限 5 分、締めの合図 1 分、トークンの余裕 5 分", func(t *testing.T) {
		config := parseConfig(t)

		if config.RingTimeout != time.Minute {
			t.Errorf("呼び出しの上限 = %s, want 1 分", config.RingTimeout)
		}
		if config.MaxCall != 5*time.Minute {
			t.Errorf("電話の長さの上限 = %s, want 5 分", config.MaxCall)
		}
		if config.WrapUpBefore != time.Minute {
			t.Errorf("締めの合図を送る時間 = %s, want 1 分", config.WrapUpBefore)
		}
		if config.TokenMargin != 5*time.Minute {
			t.Errorf("トークンの有効期限の余裕 = %s, want 5 分", config.TokenMargin)
		}
	})

	t.Run("フラグで 4 つの時間を変えられる", func(t *testing.T) {
		config := parseConfig(t,
			"--ring-timeout=2m",
			"--max-call=3m",
			"--wrap-up-before=30s",
			"--token-margin=4m",
		)

		if config.RingTimeout != 2*time.Minute {
			t.Errorf("呼び出しの上限 = %s, want 2 分", config.RingTimeout)
		}
		if config.MaxCall != 3*time.Minute {
			t.Errorf("電話の長さの上限 = %s, want 3 分", config.MaxCall)
		}
		if config.WrapUpBefore != 30*time.Second {
			t.Errorf("締めの合図を送る時間 = %s, want 30 秒", config.WrapUpBefore)
		}
		if config.TokenMargin != 4*time.Minute {
			t.Errorf("トークンの有効期限の余裕 = %s, want 4 分", config.TokenMargin)
		}
	})
}

func TestSummaryModelFlag(t *testing.T) {
	t.Run("既定のまとめのモデルは gemini-3.6-flash である", func(t *testing.T) {
		config := parseConfig(t)

		if config.SummaryModel != "gemini-3.6-flash" {
			t.Errorf("まとめのモデル = %q, want gemini-3.6-flash", config.SummaryModel)
		}
	})

	t.Run("--summary-model でまとめのモデルを選べる", func(t *testing.T) {
		config := parseConfig(t, "--summary-model=gemini-3.6-pro")

		if config.SummaryModel != "gemini-3.6-pro" {
			t.Errorf("まとめのモデル = %q, want gemini-3.6-pro", config.SummaryModel)
		}
	})
}

func TestWatchedPersonFlag(t *testing.T) {
	t.Run("--watched-person で、電話をかける見守る方の ID を受け取る", func(t *testing.T) {
		config := parseConfig(t, "--watched-person=hanako-id")

		if config.WatchedPerson != "hanako-id" {
			t.Errorf("見守る方 = %q, want hanako-id", config.WatchedPerson)
		}
	})

	t.Run("--watched-person の見守る方が Firestore にいなければ、起動を断る", func(t *testing.T) {
		t.Setenv("GEMINI_API_KEY", "test-key")
		config := parseConfig(t, "--watched-person=nobody")

		err := run(config)
		if err == nil {
			t.Fatal("起動してしまった")
		}
		for _, want := range []string{"--watched-person", "nobody", "起動できません"} {
			if !strings.Contains(err.Error(), want) {
				t.Errorf("起動を断るメッセージ %q に %q がない", err.Error(), want)
			}
		}
	})
}

func TestRunRefusesWhenTheCallOutlastsTheConnection(t *testing.T) {
	hanako := server.Config{WatchedPerson: "hanako-id"}

	t.Run("呼び出しの上限と電話の長さの上限の合計が 10 分を超えると、起動を断る", func(t *testing.T) {
		config := hanako
		config.RingTimeout = 6 * time.Minute
		config.MaxCall = 5 * time.Minute

		err := run(config)
		if err == nil {
			t.Fatal("起動してしまった")
		}
		for _, want := range []string{"--ring-timeout", "--max-call", "6 分", "5 分", "10 分", "起動できません"} {
			if !strings.Contains(err.Error(), want) {
				t.Errorf("起動を断るメッセージ %q に %q がない", err.Error(), want)
			}
		}
	})

	t.Run("締めの合図を送る時間が電話の長さの上限より長いと、起動を断る", func(t *testing.T) {
		config := hanako
		config.MaxCall = 30 * time.Second
		config.WrapUpBefore = time.Minute

		err := run(config)
		if err == nil {
			t.Fatal("起動してしまった")
		}
		for _, want := range []string{"--wrap-up-before", "--max-call", "1 分", "30 秒", "起動できません"} {
			if !strings.Contains(err.Error(), want) {
				t.Errorf("起動を断るメッセージ %q に %q がない", err.Error(), want)
			}
		}
	})

	t.Run("締めの合図を送る時間が電話の長さの上限と同じなら、その時間では起動を断らない", func(t *testing.T) {
		t.Setenv("GEMINI_API_KEY", "")
		config := hanako
		config.MaxCall = time.Minute
		config.WrapUpBefore = time.Minute

		err := run(config)
		if err == nil || !strings.Contains(err.Error(), "GEMINI_API_KEY") {
			t.Fatalf("合図と上限が同じなら、その時間では断らず API キーの確認まで進む。got %v", err)
		}
	})

	t.Run("合計がちょうど 10 分なら、時間を理由に起動を断らない", func(t *testing.T) {
		t.Setenv("GEMINI_API_KEY", "")
		config := hanako
		config.RingTimeout = 6 * time.Minute
		config.MaxCall = 4 * time.Minute

		err := run(config)
		if err == nil || !strings.Contains(err.Error(), "GEMINI_API_KEY") {
			t.Fatalf("ちょうど 10 分なら時間では断らず、API キーの確認まで進む。got %v", err)
		}
	})
}

func parseConfig(t *testing.T, args ...string) server.Config {
	t.Helper()
	fs := flag.NewFlagSet("backend", flag.ContinueOnError)
	var config server.Config
	defineFlags(fs, &config)
	if err := fs.Parse(args); err != nil {
		t.Fatal(err)
	}
	return config
}
