package phone

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/internal/clock"
	"github.com/gesop0n/kazokuai/internal/clock/clocktest"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

func TestPhoneWebSocketURL(t *testing.T) {
	got, err := phoneWebSocketURL("https://kazokuai.example.run.app", "hanako")
	if err != nil || got != "wss://kazokuai.example.run.app/phone?watchedPerson=hanako" {
		t.Fatalf("https = %q, %v", got, err)
	}
	got, err = phoneWebSocketURL("http://localhost:8080", "hanako")
	if err != nil || got != "ws://localhost:8080/phone?watchedPerson=hanako" {
		t.Fatalf("http = %q, %v", got, err)
	}
	got, err = phoneWebSocketURL("https://kazokuai.example.run.app/", "hanako")
	if err != nil || got != "wss://kazokuai.example.run.app/phone?watchedPerson=hanako" {
		t.Fatalf("末尾の / = %q, %v", got, err)
	}
	if _, err := phoneWebSocketURL("ftp://kazokuai.example", "hanako"); err == nil {
		t.Fatal("ftp を受け入れた")
	}
}

func TestDeviceUsesWSSForAnHTTPSBackend(t *testing.T) {
	connected := make(chan struct{}, 1)
	done := make(chan struct{})
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != protocol.PhonePath || r.URL.Query().Get("watchedPerson") != "hanako" {
			http.NotFound(w, r)
			return
		}
		if r.Header.Get(protocol.PhoneSecretHeader) != "dev-phone-secret" {
			http.Error(w, "合言葉が違います", http.StatusUnauthorized)
			return
		}
		conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
		if err != nil {
			return
		}
		connected <- struct{}{}
		select {
		case <-done:
			conn.CloseNow()
		}
	}))
	t.Cleanup(func() {
		close(done)
		srv.Close()
	})

	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	device := &Device{
		Backend:       srv.URL,
		Secret:        "dev-phone-secret",
		WatchedPerson: "hanako",
		HTTP:          srv.Client(),
		Out:           io.Discard,
		Clock:         clock.Real{},
	}
	go device.Run(ctx)

	select {
	case <-connected:
	case <-time.After(2 * time.Second):
		t.Fatal("https のバックエンドに wss でつながらなかった")
	}
}

func TestDeviceRedialsWhenTheBackendStopsAnsweringPing(t *testing.T) {
	accepted := make(chan struct{}, 2)
	done := make(chan struct{})
	// サーバーは接続を受けるが読まない。pong が返らないので、電話機は半分切れたとみる。
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get(protocol.PhoneSecretHeader) != "dev-phone-secret" {
			http.Error(w, "合言葉が違います", http.StatusUnauthorized)
			return
		}
		conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
		if err != nil {
			return
		}
		accepted <- struct{}{}
		select {
		case <-done:
			conn.CloseNow()
		}
	}))
	t.Cleanup(func() {
		close(done)
		srv.Close()
	})

	clk := clocktest.New(time.Date(2026, 1, 2, 9, 0, 0, 0, time.UTC))
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	device := &Device{
		Backend:       srv.URL,
		Secret:        "dev-phone-secret",
		WatchedPerson: "hanako",
		Out:           io.Discard,
		Clock:         clk,
	}
	go device.Run(ctx)

	select {
	case <-accepted:
	case <-time.After(2 * time.Second):
		t.Fatal("最初の接続が来なかった")
	}

	clk.Advance(30 * time.Second)
	deadline := time.Now().Add(4 * time.Second)
	for {
		select {
		case <-accepted:
			return
		default:
		}
		if time.Now().After(deadline) {
			t.Fatal("pong が無い接続のあと、つなぎ直さなかった")
		}
		clk.Advance(time.Second)
		time.Sleep(50 * time.Millisecond)
	}
}

func TestPostBackendJoinsATrailingSlash(t *testing.T) {
	var path, secret string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path = r.URL.Path
		secret = r.Header.Get(protocol.PhoneSecretHeader)
		w.WriteHeader(http.StatusNoContent)
	}))
	t.Cleanup(srv.Close)

	for _, base := range []string{srv.URL, srv.URL + "/"} {
		path, secret = "", ""
		device := &Device{Backend: base, Secret: "dev-phone-secret"}
		resp, err := device.postBackend(context.Background(), protocol.TokenPath, []byte(`{}`))
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if path != "/token" {
			t.Errorf("Backend %s のパス = %q, want /token", base, path)
		}
		if secret != "dev-phone-secret" {
			t.Errorf("合言葉 = %q", secret)
		}
	}
}
