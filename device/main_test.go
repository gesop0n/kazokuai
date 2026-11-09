package main

import (
	"bytes"
	"net/http"
	"runtime"
	"strings"
	"testing"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

func TestMissingWatchedPersonUsesThePhoneIdentity(t *testing.T) {
	opts, err := parseArgs(nil, func(string) string { return "" })
	if err != nil {
		t.Fatal(err)
	}
	if opts.person != "" || opts.backend != "http://localhost:8080" || opts.phoneFile != "" {
		t.Fatalf("起動 = %+v, want 見守る方とファイルは空、バックエンドは手元", opts)
	}
}

func TestBackendFlag(t *testing.T) {
	opts, err := parseArgs([]string{"--watched-person", "hanako"}, func(string) string { return "" })
	if err != nil {
		t.Fatal(err)
	}
	if opts.person != "hanako" || opts.backend != "http://localhost:8080" {
		t.Fatalf("既定 = %s %s, want hanako と http://localhost:8080", opts.person, opts.backend)
	}

	opts, err = parseArgs([]string{"--watched-person", "hanako", "--backend", "https://kazokuai.example.run.app"}, func(string) string { return "" })
	if err != nil || opts.backend != "https://kazokuai.example.run.app" {
		t.Fatalf("--backend = %s, %v", opts.backend, err)
	}

	_, err = parseArgs([]string{"--watched-person", "hanako", "--backend="}, func(string) string { return "" })
	if err == nil || !strings.Contains(err.Error(), "--backend") {
		t.Fatalf("空の URL = %v", err)
	}
}

func TestWatchedPersonComesFromTheFlagOrTheEnvironment(t *testing.T) {
	env := func(key string) string {
		if key == "KAZOKUAI_WATCHED_PERSON" {
			return " from-env "
		}
		return ""
	}
	opts, err := parseArgs(nil, env)
	if err != nil || opts.person != "from-env" {
		t.Fatalf("環境変数 = %+v, %v", opts, err)
	}
	opts, err = parseArgs([]string{"--watched-person", "from-flag"}, env)
	if err != nil || opts.person != "from-flag" {
		t.Fatalf("フラグ = %+v, %v", opts, err)
	}
}

func TestPhoneFileComesFromTheFlagOrTheSetting(t *testing.T) {
	env := func(key string) string {
		if key == "KAZOKUAI_PHONE_FILE" {
			return " /tmp/from-env.json "
		}
		return ""
	}
	opts, err := parseArgs(nil, env)
	if err != nil || opts.phoneFile != "/tmp/from-env.json" {
		t.Fatalf("設定 = %+v, %v", opts, err)
	}
	opts, err = parseArgs([]string{"--phone-file", "/tmp/from-flag.json"}, env)
	if err != nil || opts.phoneFile != "/tmp/from-flag.json" {
		t.Fatalf("フラグ = %+v, %v", opts, err)
	}
}

func TestCheckNamesThePartBeforeOpeningAnything(t *testing.T) {
	err := run([]string{"check"})
	if err == nil || !strings.Contains(err.Error(), "speaker") {
		t.Fatalf("部品なし = %v", err)
	}
	err = run([]string{"check", "lamp"})
	if err == nil || !strings.Contains(err.Error(), "lamp") {
		t.Fatalf("範囲外 = %v", err)
	}
}

func TestCheckRunsOnThePhone(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("Linux では部品を開くので、ここでは動かさない")
	}
	for _, part := range []string{"hook", "ringer", "keypad"} {
		err := run([]string{"check", part})
		if err == nil || !strings.Contains(err.Error(), "電話機") {
			t.Fatalf("Mac の %s = %v", part, err)
		}
	}
}

func TestPhoneSecretUsesTheDevSecretWhenUnset(t *testing.T) {
	if got := phoneSecret(""); got != "dev-phone-secret" {
		t.Fatalf("未設定 = %q, want dev-phone-secret", got)
	}
	if got := phoneSecret("production-secret"); got != "production-secret" {
		t.Fatalf("設定済み = %q", got)
	}
	if got := phoneSecret(" \n"); got != "dev-phone-secret" {
		t.Fatalf("空白だけ = %q, want dev-phone-secret", got)
	}
}

func TestPhoneSecretTrimsSurroundingSpace(t *testing.T) {
	got := phoneSecret(" \nshared-secret\r\n")
	if got != "shared-secret" {
		t.Fatalf("合言葉 = %q, want shared-secret", got)
	}
	req, err := http.NewRequest(http.MethodPost, "http://backend.example/token", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set(protocol.PhoneSecretHeader, got)
	var buf bytes.Buffer
	if err := req.Write(&buf); err != nil {
		t.Fatalf("合言葉をヘッダーに書けなかった: %v", err)
	}
	if !bytes.Contains(buf.Bytes(), []byte("Kazokuai-Secret: shared-secret\r\n")) {
		t.Fatalf("ヘッダーに合言葉がない: %s", buf.String())
	}
}
