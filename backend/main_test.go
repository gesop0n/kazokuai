package main

import (
	"context"
	"flag"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/protocol"
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

func TestRunRefusesWhenTheCallOutlastsTheConnection(t *testing.T) {
	hanako := server.Config{}

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

func TestGeminiRequestWithTrailingNewline(t *testing.T) {
	const key = "kazokuai-gemini-key"
	var gotKey string
	gemini := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotKey = r.Header.Get("X-Goog-Api-Key")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"candidates":[{"content":{"role":"model","parts":[{"text":"届きました"}]}}]}`))
	}))
	t.Cleanup(gemini.Close)

	apiKey, err := readGeminiAPIKey(" \n" + key + "\r\n")
	if err != nil {
		t.Fatal(err)
	}
	client, err := newGeminiClient(t.Context(), apiKey, genai.HTTPOptions{BaseURL: gemini.URL})
	if err != nil {
		t.Fatal(err)
	}
	resp, err := client.Models.GenerateContent(
		t.Context(),
		"gemini-3.6-flash",
		[]*genai.Content{genai.NewContentFromText("こんにちは", genai.RoleUser)},
		nil,
	)
	if err != nil {
		t.Fatalf("Gemini へのリクエスト: %v", err)
	}
	if resp.Text() != "届きました" {
		t.Fatalf("Gemini の返答 = %q, want 届きました", resp.Text())
	}
	if gotKey != key {
		t.Fatalf("X-Goog-Api-Key = %q, want %s", gotKey, key)
	}
}

func TestGeminiAPIKeyOfOnlySpaceIsRefused(t *testing.T) {
	_, err := readGeminiAPIKey(" \n")
	if err == nil || !strings.Contains(err.Error(), "GEMINI_API_KEY") {
		t.Fatalf("空白だけのキー = %v, want GEMINI_API_KEY が要ると断る", err)
	}
}

func TestListenAddr(t *testing.T) {
	got, err := listenAddr("")
	if err != nil || got != "0.0.0.0:8080" {
		t.Fatalf("空 = %q, %v", got, err)
	}
	got, err = listenAddr("9090")
	if err != nil || got != "0.0.0.0:9090" {
		t.Fatalf("9090 = %q, %v", got, err)
	}
	for _, port := range []string{"0", "65536", "eighty"} {
		if _, err := listenAddr(port); err == nil || !strings.Contains(err.Error(), "1 から 65535") {
			t.Errorf("PORT=%s のエラー = %v", port, err)
		}
	}
}

func TestServeStopsPhonesWhenTheContextEnds(t *testing.T) {
	handler := server.New(server.Config{
		ProjectID:   "demo-kazokuai",
		PhoneSecret: "dev-phone-secret",
	}, server.Firebase{}, nil, nil, nil)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	errc := make(chan error, 1)
	go func() { errc <- serve(ctx, ln, handler) }()

	header := http.Header{}
	header.Set(protocol.PhoneSecretHeader, "dev-phone-secret")
	wsURL := "ws://" + ln.Addr().String() + "/phone?watchedPerson=hanako"
	var conn *websocket.Conn
	deadline := time.Now().Add(2 * time.Second)
	for {
		c, _, dialErr := websocket.Dial(context.Background(), wsURL, &websocket.DialOptions{HTTPHeader: header})
		if dialErr == nil {
			conn = c
			break
		}
		if time.Now().After(deadline) {
			t.Fatal(dialErr)
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Cleanup(func() { conn.CloseNow() })
	waitUntilConnected(t, handler, "hanako")

	cancel()
	select {
	case err := <-errc:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("context が終わってもサーバーが止まらなかった")
	}
	readCtx, stop := context.WithTimeout(context.Background(), time.Second)
	defer stop()
	if _, _, err := conn.Read(readCtx); err == nil {
		t.Fatal("止めたあとも電話機の接続が生きている")
	}
}

func waitUntilConnected(t *testing.T, handler *server.Handler, personID string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for !handler.Connected(personID) {
		if time.Now().After(deadline) {
			t.Fatal("電話機がつながらなかった")
		}
		time.Sleep(time.Millisecond)
	}
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
