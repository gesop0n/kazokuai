package main

import (
	"runtime"
	"strings"
	"testing"
)

func TestRunRequiresWatchedPerson(t *testing.T) {
	err := run(nil)
	if err == nil || !strings.Contains(err.Error(), "--watched-person") {
		t.Fatalf("起動 = %v, want --watched-person が要ると伝えて、受話器を開かない", err)
	}
}

func TestBackendFlag(t *testing.T) {
	person, backend, err := parseArgs([]string{"--watched-person", "hanako"})
	if err != nil {
		t.Fatal(err)
	}
	if person != "hanako" || backend != "http://localhost:8080" {
		t.Fatalf("既定 = %s %s, want hanako と http://localhost:8080", person, backend)
	}

	_, backend, err = parseArgs([]string{"--watched-person", "hanako", "--backend", "https://kazokuai.example.run.app"})
	if err != nil || backend != "https://kazokuai.example.run.app" {
		t.Fatalf("--backend = %s, %v", backend, err)
	}

	_, _, err = parseArgs([]string{"--watched-person", "hanako", "--backend="})
	if err == nil || !strings.Contains(err.Error(), "--backend") {
		t.Fatalf("空の URL = %v", err)
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
	for _, part := range []string{"hook", "keypad"} {
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
}
