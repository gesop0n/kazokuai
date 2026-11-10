package phone

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"syscall"
	"testing"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

func TestIdentityFileIsPrivateAndStable(t *testing.T) {
	path := filepath.Join(t.TempDir(), "kazokuai", "phone.json")
	old := syscall.Umask(0)
	t.Cleanup(func() { syscall.Umask(old) })

	first, err := LoadOrCreateIdentity(path)
	if err != nil {
		t.Fatal(err)
	}
	if first.ID == "" || first.Key == "" || first.ID == first.Key {
		t.Fatal("ID と鍵が作られなかった")
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("ファイルの権限 = %o, want 600", info.Mode().Perm())
	}
	dir, err := os.Stat(filepath.Dir(path))
	if err != nil {
		t.Fatal(err)
	}
	if dir.Mode().Perm() != 0o700 {
		t.Fatalf("ディレクトリの権限 = %o, want 700", dir.Mode().Perm())
	}

	second, err := LoadOrCreateIdentity(path)
	if err != nil {
		t.Fatal(err)
	}
	if second.ID != first.ID || second.Key != first.Key {
		t.Fatal("次の読み込みの ID と鍵が、最初のファイルと違う")
	}
}

func TestBrokenIdentityFileIsLeftInPlace(t *testing.T) {
	path := filepath.Join(t.TempDir(), "phone.json")
	if err := os.WriteFile(path, []byte("{"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadOrCreateIdentity(path); err == nil {
		t.Fatal("壊れたファイルを受け入れた")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "{" {
		t.Fatal("壊れたファイルを書き換えた")
	}
}

func TestIdentityPath(t *testing.T) {
	configDir := filepath.Join("/Users/me/Library/Application Support")
	empty := func(string) string { return "" }

	got, err := IdentityPath("darwin", empty, configDir)
	want := filepath.Join(configDir, "kazokuai", IdentityFileName)
	if err != nil || got != want {
		t.Fatalf("Mac = %s, %v, want %s", got, err, want)
	}

	got, err = IdentityPath("linux", empty, configDir)
	want = filepath.Join(LinuxStateDir, IdentityFileName)
	if err != nil || got != want {
		t.Fatalf("Pi = %s, %v, want %s", got, err, want)
	}

	withState := func(key string) string {
		if key == "STATE_DIRECTORY" {
			return "/var/lib/kazokuai:/var/lib/other"
		}
		return ""
	}
	got, err = IdentityPath("linux", withState, configDir)
	if err != nil || got != "/var/lib/kazokuai/phone.json" {
		t.Fatalf("状態ディレクトリ = %s, %v", got, err)
	}

	withSetting := func(key string) string {
		if key == PhoneFileEnv {
			return "/tmp/custom.json"
		}
		if key == "STATE_DIRECTORY" {
			return "/var/lib/kazokuai"
		}
		return ""
	}
	for _, goos := range []string{"linux", "darwin"} {
		got, err = IdentityPath(goos, withSetting, configDir)
		if err != nil || got != "/tmp/custom.json" {
			t.Fatalf("%s の設定 = %s, %v", goos, got, err)
		}
	}

	if _, err := IdentityPath("darwin", empty, ""); err == nil {
		t.Fatal("設定ディレクトリが無い Mac を受け入れた")
	}
}

func TestUnknownPhoneRegistersAgainForTheToken(t *testing.T) {
	const id = "phone-1"
	const key = "key-1"
	var registers int
	var tokens int
	var gotID, gotKey, gotSecret string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case protocol.PhoneRegisterPath:
			registers++
			gotID = r.Header.Get(protocol.PhoneIDHeader)
			gotKey = r.Header.Get(protocol.PhoneKeyHeader)
			gotSecret = r.Header.Get(protocol.PhoneSecretHeader)
			w.WriteHeader(http.StatusCreated)
		case protocol.TokenPath:
			tokens++
			if tokens == 1 {
				http.Error(w, protocol.PhoneAnswerUnknownPhone, http.StatusNotFound)
				return
			}
			if r.Header.Get(protocol.PhoneIDHeader) == "" || r.Header.Get(protocol.PhoneKeyHeader) == "" || r.Header.Get(protocol.PhoneSecretHeader) != "" {
				http.Error(w, "auth", http.StatusUnauthorized)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			io.WriteString(w, `{"token":"tok","model":"m","times":{"ringTimeout":60000000000,"maxCall":300000000000,"wrapUpBefore":60000000000}}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)

	device := &Device{
		Backend: srv.URL,
		Secret:  protocol.DevPhoneSecret,
		ID:      id,
		Key:     key,
	}
	token, err := device.fetchToken(context.Background(), "call-1")
	if err != nil {
		t.Fatal(err)
	}
	if token.Token != "tok" {
		t.Fatalf("トークン = %q, want tok", token.Token)
	}
	if registers != 1 {
		t.Fatalf("登録 = %d 回, want 知らない ID のあとに 1 回", registers)
	}
	if gotID != id || gotKey != key || gotSecret != protocol.DevPhoneSecret {
		t.Fatal("登録し直した ID と鍵と合言葉が違う")
	}
}
