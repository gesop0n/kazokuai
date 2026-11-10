package server_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/clock"
	"github.com/gesop0n/kazokuai/internal/clock/clocktest"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

func TestResolveProjectFrom(t *testing.T) {
	t.Run("エミュレーターがあってプロジェクトが空なら demo-kazokuai", func(t *testing.T) {
		got, err := server.ResolveProjectFrom("", "127.0.0.1:8081", "127.0.0.1:9099")
		if err != nil || got != "demo-kazokuai" {
			t.Fatalf("got %q, %v", got, err)
		}
	})

	t.Run("エミュレーターと demo- のプロジェクトはその ID を使う", func(t *testing.T) {
		got, err := server.ResolveProjectFrom("demo-other", "127.0.0.1:8081", "127.0.0.1:9099")
		if err != nil || got != "demo-other" {
			t.Fatalf("got %q, %v", got, err)
		}
	})

	t.Run("エミュレーターなのに本番のプロジェクトなら断る", func(t *testing.T) {
		_, err := server.ResolveProjectFrom("kazokuai-prod", "127.0.0.1:8081", "127.0.0.1:9099")
		if err == nil || !strings.Contains(err.Error(), "demo-") {
			t.Fatalf("got %v", err)
		}
	})

	t.Run("片方のエミュレーターだけでは断る", func(t *testing.T) {
		if _, err := server.ResolveProjectFrom("", "127.0.0.1:8081", ""); err == nil || !strings.Contains(err.Error(), "FIREBASE_AUTH_EMULATOR_HOST") {
			t.Fatalf("Auth が無い: %v", err)
		}
		if _, err := server.ResolveProjectFrom("", "", "127.0.0.1:9099"); err == nil || !strings.Contains(err.Error(), "FIRESTORE_EMULATOR_HOST") {
			t.Fatalf("Firestore が無い: %v", err)
		}
	})

	t.Run("エミュレーターが無ければ本番のプロジェクトの ID が要る", func(t *testing.T) {
		got, err := server.ResolveProjectFrom("kazokuai-prod", "", "")
		if err != nil || got != "kazokuai-prod" {
			t.Fatalf("got %q, %v", got, err)
		}
		if _, err := server.ResolveProjectFrom("", "", ""); err == nil || !strings.Contains(err.Error(), "GOOGLE_CLOUD_PROJECT") {
			t.Fatalf("空: %v", err)
		}
		if _, err := server.ResolveProjectFrom("demo-kazokuai", "", ""); err == nil || !strings.Contains(err.Error(), "エミュレーター") {
			t.Fatalf("demo- だけ: %v", err)
		}
	})
}

func TestSecretFor(t *testing.T) {
	t.Run("環境変数にあれば、前後の空白を除いてそれを使う", func(t *testing.T) {
		got, err := server.SecretFor("kazokuai-prod", " \nproduction-secret\r\n")
		if err != nil || got != "production-secret" {
			t.Fatalf("got %q, %v", got, err)
		}
	})

	t.Run("空白だけなら未設定と同じ", func(t *testing.T) {
		got, err := server.SecretFor("demo-kazokuai", " \n")
		if err != nil || got != "dev-phone-secret" {
			t.Fatalf("demo = %q, %v", got, err)
		}
		if _, err := server.SecretFor("kazokuai-prod", " \n"); err == nil || !strings.Contains(err.Error(), "PHONE_SECRET") {
			t.Fatalf("本番の空白だけ = %v", err)
		}
	})

	t.Run("demo- で未設定なら開発用の合言葉", func(t *testing.T) {
		got, err := server.SecretFor("demo-kazokuai", "")
		if err != nil || got != "dev-phone-secret" {
			t.Fatalf("got %q, %v", got, err)
		}
	})

	t.Run("本番で未設定なら断る", func(t *testing.T) {
		_, err := server.SecretFor("kazokuai-prod", "")
		if err == nil || !strings.Contains(err.Error(), "PHONE_SECRET") {
			t.Fatalf("got %v", err)
		}
	})
}

func TestPhoneSecretWithTrailingNewlineStillPasses(t *testing.T) {
	secret, err := server.SecretFor("kazokuai-prod", " \nshared-secret\r\n")
	if err != nil {
		t.Fatal(err)
	}
	if secret != "shared-secret" {
		t.Fatalf("読んだ合言葉 = %q, want shared-secret", secret)
	}
	srv := newDemoServer(t, "kazokuai-prod", secret, nil)
	resp := call(t, srv.URL, http.MethodPost, "/token", secret, `{}`)
	if resp.status != http.StatusBadRequest {
		t.Fatalf("合言葉の確かめ = %d, want 400（合言葉では断らない）: %s", resp.status, resp.body)
	}
}

func TestPhoneConnectionLogs(t *testing.T) {
	const secret = "phone-secret-do-not-log"
	var logs lockedBuffer
	logger := log.New(&logs, "", log.LstdFlags)
	srv, handler := newLoggingServer(t, secret, logger, nil)
	person, token := registerHanako(t, srv.URL)

	conn := dialPhone(t, srv.URL, person, secret)
	readPhone(conn)
	waitConnected(t, handler, person, true)
	waitForLog(t, &logs, "電話機がつながりました。見守る方: "+person)
	if strings.Contains(logs.String(), secret) {
		t.Fatal("つながったログに合言葉がある")
	}

	if err := conn.Close(websocket.StatusNormalClosure, "切った-"+secret); err != nil {
		t.Fatal(err)
	}
	waitConnected(t, handler, person, false)
	waitForLog(t, &logs, "電話機が切れました。見守る方: "+person)
	waitForLog(t, &logs, "理由: 切った-[合言葉]")
	if strings.Contains(logs.String(), secret) {
		t.Fatal("切れたログに合言葉がある")
	}

	resp := postJSON(t, srv.URL, "/calls/now", "Bearer "+token, `{"message": "金曜の通院", "script": "ハナさん、美咲さんからです。"}`)
	if resp.status != http.StatusConflict || !strings.Contains(string(resp.body), protocol.PhoneNotConnected) {
		t.Fatalf("今すぐ通話 = %d %s, want 409 phone_not_connected", resp.status, resp.body)
	}
	waitForLog(t, &logs, "今すぐ通話を断りました。電話機がつながっていません。見守る方: "+person)
	if strings.Contains(logs.String(), secret) {
		t.Fatal("断ったログに合言葉がある")
	}
}

func TestRefusedCallLogsThePersonWhenThePhoneDropsDuringCreation(t *testing.T) {
	const secret = "phone-secret-do-not-log"
	var logs lockedBuffer
	logger := log.New(&logs, "", 0)
	entered := make(chan struct{})
	release := make(chan struct{})
	var once sync.Once
	letGo := func() { once.Do(func() { close(release) }) }
	t.Cleanup(letGo)
	clk := &holdClock{Clock: clock.Real{}, entered: entered, release: release}
	srv, handler := newLoggingServer(t, secret, logger, clk)
	person, token := registerHanako(t, srv.URL)
	conn := dialPhone(t, srv.URL, person, secret)
	readPhone(conn)
	waitConnected(t, handler, person, true)

	done := make(chan response, 1)
	go func() {
		req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, srv.URL+"/calls/now", strings.NewReader(`{"message": "金曜の通院", "script": "ハナさん、美咲さんからです。"}`))
		if err != nil {
			done <- response{status: -1, body: []byte(err.Error())}
			return
		}
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+token)
		got, err := http.DefaultClient.Do(req)
		if err != nil {
			done <- response{status: -1, body: []byte(err.Error())}
			return
		}
		defer got.Body.Close()
		body, err := io.ReadAll(got.Body)
		if err != nil {
			done <- response{status: got.StatusCode, body: []byte(err.Error())}
			return
		}
		done <- response{status: got.StatusCode, body: body}
	}()
	// 作成が時計に着くまでに、家族と電話機の読み取りと、通話の一覧のトランザクションがある。
	// エミュレーターがほかのテストと取り合っていると、2 秒では着かない。
	select {
	case <-entered:
	case <-time.After(slowEmulatorBound):
		t.Fatal("電話を作り始める前に止まった")
	}
	if err := conn.Close(websocket.StatusNormalClosure, "作成中に切れた"); err != nil {
		t.Fatal(err)
	}
	// 切れたことはログで待つ。Connected は電話機の読み取りに失敗すると、つながっていても切れたと返す。
	// そのあいだに作成を進めると、電話が届いて、断ったログを確かめられない。
	waitForLog(t, &logs, "電話機が切れました。見守る方: "+person)
	waitConnected(t, handler, person, false)
	letGo()

	// 止めていた作成のトランザクションは、やり直しの待ちが 1 秒から倍々に伸びる。
	// 戻ったあとの 409 と、届かなかった電話が残らないことと、見守る方の ID は、これまでどおり確かめる。
	var resp response
	select {
	case resp = <-done:
	case <-time.After(slowEmulatorBound):
		t.Fatal("今すぐ通話が戻らなかった")
	}
	if resp.status != http.StatusConflict || !strings.Contains(string(resp.body), protocol.PhoneNotConnected) {
		t.Fatalf("今すぐ通話 = %d %s, want 409 phone_not_connected", resp.status, resp.body)
	}
	if callCount(t, person) != 0 {
		t.Fatalf("届かなかった電話が残っている")
	}
	waitForLog(t, &logs, "今すぐ通話を断りました。電話機がつながっていません。見守る方: "+person)
	if strings.Contains(logs.String(), secret) {
		t.Fatal("断ったログに合言葉がある")
	}
}

func TestDropLogStaysOneLineWhenTheReasonHasALineBreak(t *testing.T) {
	const secret = "phone-secret-do-not-log"
	var logs lockedBuffer
	logger := log.New(&logs, "", 0)
	srv, handler := newLoggingServer(t, secret, logger, nil)
	person, _ := registerHanako(t, srv.URL)
	conn := dialPhone(t, srv.URL, person, secret)
	readPhone(conn)
	waitConnected(t, handler, person, true)

	if err := conn.Close(websocket.StatusNormalClosure, "Wi-Fi disconnected\r\n"+secret); err != nil {
		t.Fatal(err)
	}
	waitConnected(t, handler, person, false)
	waitForLog(t, &logs, "電話機が切れました。見守る方: "+person)

	text := logs.String()
	lines := strings.Split(strings.TrimRight(text, "\n"), "\n")
	if len(lines) != 2 {
		t.Fatalf("ログの行数 = %d, want つながったときと切れたときの 2 行:\n%s", len(lines), text)
	}
	if !strings.Contains(lines[1], person) || !strings.Contains(lines[1], `Wi-Fi disconnected\r\n[合言葉]`) {
		t.Fatalf("切れた行 = %q", lines[1])
	}
	if strings.Contains(text, secret) {
		t.Fatal("切れたログに合言葉がある")
	}
}

// holdClock は、最初の Now で入り、release が閉じるまで電話の作成を止める。
type holdClock struct {
	clock.Clock
	once    sync.Once
	entered chan struct{}
	release chan struct{}
}

func (c *holdClock) Now() time.Time {
	c.once.Do(func() {
		close(c.entered)
		<-c.release
	})
	return c.Clock.Now()
}

func TestPhoneSecretGatesTheDeviceRoutes(t *testing.T) {
	srv := newDemoServer(t, "demo-kazokuai", "dev-phone-secret", nil)

	t.Run("合言葉がないとトークンも報告も WebSocket も断る", func(t *testing.T) {
		for _, target := range []struct{ method, path string }{
			{http.MethodPost, "/token"},
			{http.MethodPost, "/calls"},
			{http.MethodGet, "/phone?watchedPerson=hanako"},
		} {
			resp := call(t, srv.URL, target.method, target.path, "", `{}`)
			if resp.status != http.StatusUnauthorized || !strings.Contains(string(resp.body), "合言葉が違います") {
				t.Errorf("%s %s = %d %s, want 401 合言葉が違います", target.method, target.path, resp.status, resp.body)
			}
		}
	})

	t.Run("違う合言葉でも断る", func(t *testing.T) {
		resp := call(t, srv.URL, http.MethodPost, "/token", "other-secret", `{}`)
		if resp.status != http.StatusUnauthorized {
			t.Errorf("ステータス = %d, want 401: %s", resp.status, resp.body)
		}
	})

	t.Run("合言葉があれば、中身が空でも合言葉では断らない", func(t *testing.T) {
		for _, path := range []string{"/token", "/calls"} {
			resp := call(t, srv.URL, http.MethodPost, path, "dev-phone-secret", `{}`)
			if resp.status != http.StatusBadRequest {
				t.Errorf("POST %s = %d, want 400: %s", path, resp.status, resp.body)
			}
		}
	})

	t.Run("合言葉があれば WebSocket はつながる", func(t *testing.T) {
		conn := dialPhone(t, srv.URL, "hanako", "dev-phone-secret")
		conn.CloseNow()
	})

	t.Run("サーバーの合言葉が空なら、開発用の合言葉でも断る", func(t *testing.T) {
		open := newDemoServer(t, "demo-kazokuai", "", nil)
		resp := call(t, open.URL, http.MethodPost, "/token", "dev-phone-secret", `{}`)
		if resp.status != http.StatusUnauthorized {
			t.Errorf("ステータス = %d, want 401: %s", resp.status, resp.body)
		}
	})
}

func TestAppRoutesAlsoLiveUnderAPI(t *testing.T) {
	clock := clocktest.New(time.Date(2026, 1, 2, 9, 0, 0, 0, time.UTC))
	srv, handler := newDemoServerWith(t, "demo-kazokuai", "dev-phone-secret", clock)
	misaki := signUp(t)

	resp := postJSON(t, srv.URL, "/api/watched-persons", "Bearer "+misaki.IDToken, `{"name": "山田花子", "callName": "ハナさん"}`)
	if resp.status != http.StatusCreated {
		t.Fatalf("/api/watched-persons = %d, want 201: %s", resp.status, resp.body)
	}

	for _, path := range []string{"/api/calls/now", "/api/calls/script"} {
		resp := postJSON(t, srv.URL, path, "", `{"message": "金曜の通院", "script": "ハナさんへ"}`)
		if resp.status != http.StatusUnauthorized {
			t.Errorf("%s = %d, want 401: %s", path, resp.status, resp.body)
		}
	}

	for _, target := range []struct{ method, path string }{
		{http.MethodPost, "/api/token"},
		{http.MethodGet, "/api/phone?watchedPerson=hanako"},
		{http.MethodPost, "/api/calls"},
	} {
		resp := call(t, srv.URL, target.method, target.path, "dev-phone-secret", `{}`)
		if resp.status != http.StatusNotFound {
			t.Errorf("%s %s = %d, want 404: %s", target.method, target.path, resp.status, resp.body)
		}
	}

	person := watchedPersonsOf(t, misaki.UID)
	if len(person) != 1 {
		t.Fatalf("見守る方 = %d 人, want 1", len(person))
	}
	conn := dialPhone(t, srv.URL, person[0].Ref.ID, "dev-phone-secret")
	readPhone(conn)
	waitConnected(t, handler, person[0].Ref.ID, true)

	resp = postJSON(t, srv.URL, "/api/calls/now", "Bearer "+misaki.IDToken, `{"message": "金曜の通院", "script": "ハナさん、美咲さんからです。"}`)
	if resp.status != http.StatusCreated {
		t.Fatalf("/api/calls/now = %d, want 201: %s", resp.status, resp.body)
	}
}

func TestLocalhostCORSOnlyForDemoProjects(t *testing.T) {
	demo := newDemoServer(t, "demo-kazokuai", "dev-phone-secret", nil)
	prod := newDemoServer(t, "kazokuai-prod", "dev-phone-secret", nil)

	t.Run("demo- では localhost の事前リクエストに答える", func(t *testing.T) {
		for _, origin := range []string{
			"http://localhost:5173",
			"http://127.0.0.1:5173",
			"http://[::1]:5173",
			"https://localhost:443",
		} {
			resp := options(t, demo.URL, "/watched-persons", origin)
			if resp.status != http.StatusNoContent {
				t.Errorf("%s の事前リクエスト = %d, want 204", origin, resp.status)
			}
			if got := resp.header.Get("Access-Control-Allow-Origin"); got != origin {
				t.Errorf("Allow-Origin = %q, want %s", got, origin)
			}
			if resp.header.Get("Access-Control-Allow-Methods") != "GET, POST, OPTIONS" {
				t.Errorf("Allow-Methods = %q", resp.header.Get("Access-Control-Allow-Methods"))
			}
			if resp.header.Get("Access-Control-Allow-Headers") != "Authorization, Content-Type" {
				t.Errorf("Allow-Headers = %q", resp.header.Get("Access-Control-Allow-Headers"))
			}
			if resp.header.Get("Vary") != "Origin" {
				t.Errorf("Vary = %q, want Origin", resp.header.Get("Vary"))
			}
		}
	})

	t.Run("demo- の通常のリクエストにも、その origin を返す", func(t *testing.T) {
		req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, demo.URL+"/watched-persons", strings.NewReader(`{}`))
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Origin", "http://localhost:5173")
		req.Header.Set("Content-Type", "application/json")
		got, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer got.Body.Close()
		if got.Header.Get("Access-Control-Allow-Origin") != "http://localhost:5173" {
			t.Errorf("Allow-Origin = %q", got.Header.Get("Access-Control-Allow-Origin"))
		}
		if got.StatusCode == http.StatusNoContent {
			t.Errorf("POST を事前リクエストとして終わらせてしまった")
		}
	})

	t.Run("localhost 以外には付けない", func(t *testing.T) {
		for _, origin := range []string{"https://kazokuai.example", "http://localhost.example:5173"} {
			resp := options(t, demo.URL, "/watched-persons", origin)
			if resp.header.Get("Access-Control-Allow-Origin") != "" {
				t.Errorf("%s に Allow-Origin = %q", origin, resp.header.Get("Access-Control-Allow-Origin"))
			}
		}
	})

	t.Run("本番のプロジェクトには localhost でも付けない", func(t *testing.T) {
		resp := options(t, prod.URL, "/watched-persons", "http://localhost:5173")
		if resp.header.Get("Access-Control-Allow-Origin") != "" {
			t.Errorf("Allow-Origin = %q, want 空", resp.header.Get("Access-Control-Allow-Origin"))
		}
		if resp.status == http.StatusNoContent {
			t.Errorf("本番なのに事前リクエストに 204 で答えた")
		}
	})
}

func TestDroppedCallWaitsThirtySeconds(t *testing.T) {
	t.Run("30 秒以内につながり直すと、つながらなかったにしない", func(t *testing.T) {
		clock := clocktest.New(time.Date(2026, 1, 2, 9, 0, 0, 0, time.UTC))
		srv, handler := newDemoServerWith(t, "demo-kazokuai", "dev-phone-secret", clock)
		person, token := registerHanako(t, srv.URL)
		conn := dialPhone(t, srv.URL, person, "dev-phone-secret")
		readPhone(conn)
		waitConnected(t, handler, person, true)
		callID := startNow(t, srv.URL, "/calls/now", token)

		conn.CloseNow()
		waitConnected(t, handler, person, false)
		if got := callState(t, person, callID); got != "呼び出し中" {
			t.Fatalf("切れた直後の状態 = %s, want 呼び出し中", got)
		}

		again := dialPhone(t, srv.URL, person, "dev-phone-secret")
		readPhone(again)
		waitConnected(t, handler, person, true)
		clock.Advance(30 * time.Second)

		deadline := time.Now().Add(time.Second)
		for time.Now().Before(deadline) {
			if got := callState(t, person, callID); got != "呼び出し中" {
				t.Fatalf("30 秒以内に戻ったのに状態 = %s", got)
			}
			time.Sleep(20 * time.Millisecond)
		}
		sendPhoneState(t, again, callID, "通話中")
		waitCallState(t, person, callID, "通話中")
	})

	t.Run("30 秒たっても戻らなければ、つながらなかったにする", func(t *testing.T) {
		clock := clocktest.New(time.Date(2026, 1, 2, 9, 0, 0, 0, time.UTC))
		srv, handler := newDemoServerWith(t, "demo-kazokuai", "dev-phone-secret", clock)
		person, token := registerHanako(t, srv.URL)
		conn := dialPhone(t, srv.URL, person, "dev-phone-secret")
		readPhone(conn)
		waitConnected(t, handler, person, true)
		callID := startNow(t, srv.URL, "/calls/now", token)

		conn.CloseNow()
		waitConnected(t, handler, person, false)
		clock.Advance(29 * time.Second)
		time.Sleep(200 * time.Millisecond)
		if got := callState(t, person, callID); got != "呼び出し中" {
			t.Fatalf("29 秒の状態 = %s, want 呼び出し中", got)
		}

		clock.Advance(time.Second)
		waitCallState(t, person, callID, "つながらなかった")
	})

	t.Run("猶予のあとで通話中を送り直しても、つながらなかったのまま", func(t *testing.T) {
		clock := clocktest.New(time.Date(2026, 1, 2, 9, 0, 0, 0, time.UTC))
		srv, handler := newDemoServerWith(t, "demo-kazokuai", "dev-phone-secret", clock)
		person, token := registerHanako(t, srv.URL)
		conn := dialPhone(t, srv.URL, person, "dev-phone-secret")
		readPhone(conn)
		waitConnected(t, handler, person, true)
		callID := startNow(t, srv.URL, "/calls/now", token)
		sendPhoneState(t, conn, callID, "通話中")
		waitCallState(t, person, callID, "通話中")

		conn.CloseNow()
		waitConnected(t, handler, person, false)
		clock.Advance(30 * time.Second)
		waitCallState(t, person, callID, "つながらなかった")

		again := dialPhone(t, srv.URL, person, "dev-phone-secret")
		readPhone(again)
		waitConnected(t, handler, person, true)
		sendPhoneState(t, again, callID, "通話中")
		stayCallState(t, person, callID, "つながらなかった", time.Second)
	})
}

func TestBackendDropsAPhoneThatDoesNotPong(t *testing.T) {
	t.Run("読んでいればつながったまま", func(t *testing.T) {
		clock := clocktest.New(time.Date(2026, 1, 2, 9, 0, 0, 0, time.UTC))
		srv, handler := newDemoServerWith(t, "demo-kazokuai", "dev-phone-secret", clock)
		conn := dialPhone(t, srv.URL, "reading", "dev-phone-secret")
		readPhone(conn)
		waitConnected(t, handler, "reading", true)
		// つながったと分かるのは、ping のタイマーを作る前である。
		// その前に時計を進めると ping が飛ばず、読んでいても切っていないことを確かめられない。
		clock.WaitForTimers(1)
		clock.Advance(30 * time.Second)
		deadline := time.Now().Add(1500 * time.Millisecond)
		for time.Now().Before(deadline) {
			if !handler.Connected("reading") {
				t.Fatal("pong を返している電話機を切った")
			}
			time.Sleep(20 * time.Millisecond)
		}
	})

	t.Run("読まなければ切る", func(t *testing.T) {
		clock := clocktest.New(time.Date(2026, 1, 2, 9, 0, 0, 0, time.UTC))
		srv, handler := newDemoServerWith(t, "demo-kazokuai", "dev-phone-secret", clock)
		conn := dialPhone(t, srv.URL, "silent", "dev-phone-secret")
		waitConnected(t, handler, "silent", true)
		// つながったと分かるのは、ping のタイマーを作る前である。
		// その前に時計を進めるとタイマーは鳴らず、忙しいマシンでは 3 秒待っても切れない。
		clock.WaitForTimers(1)
		clock.Advance(30 * time.Second)
		deadline := time.Now().Add(3 * time.Second)
		for handler.Connected("silent") {
			if time.Now().After(deadline) {
				t.Fatal("pong が無い電話機を切らなかった")
			}
			time.Sleep(20 * time.Millisecond)
		}
		conn.CloseNow()
	})
}

func newLoggingServer(t *testing.T, secret string, logger *log.Logger, clk clock.Clock) (*httptest.Server, *server.Handler) {
	t.Helper()
	handler := server.New(server.Config{
		ProjectID:   "demo-kazokuai",
		PhoneSecret: secret,
		Logger:      logger,
	}, emulators, nil, nil, clk)
	srv := httptest.NewServer(handler)
	t.Cleanup(func() {
		handler.Stop()
		srv.Close()
	})
	return srv, handler
}

type lockedBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *lockedBuffer) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}

func (l *lockedBuffer) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.String()
}

// slowEmulatorBound は、Firestore のエミュレーターがほかのテストと取り合っているときに、
// 確かめたい出来事を待つ上限である。トランザクションのやり直しは最大 5 回で、
// 待ちは 1 秒から倍々に伸び、その上限は 30 秒になる。その前の読み取りも 2 秒を超える。
const slowEmulatorBound = 30 * time.Second

func waitForLog(t *testing.T, logs *lockedBuffer, want string) {
	t.Helper()
	deadline := time.Now().Add(slowEmulatorBound)
	for {
		if strings.Contains(logs.String(), want) {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("ログに %q がない:\n%s", want, logs.String())
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func newDemoServer(t *testing.T, project, secret string, clk clock.Clock) *httptest.Server {
	t.Helper()
	srv, _ := newDemoServerWith(t, project, secret, clk)
	return srv
}

func newDemoServerWith(t *testing.T, project, secret string, clk clock.Clock) (*httptest.Server, *server.Handler) {
	t.Helper()
	handler := server.New(server.Config{ProjectID: project, PhoneSecret: secret}, emulators, nil, nil, clk)
	srv := httptest.NewServer(handler)
	t.Cleanup(func() {
		handler.Stop()
		srv.Close()
	})
	return srv, handler
}

func registerHanako(t *testing.T, backend string) (personID, idToken string) {
	t.Helper()
	family := signUp(t)
	resp := postJSON(t, backend, "/watched-persons", "Bearer "+family.IDToken, `{"name": "山田花子", "callName": "ハナさん"}`)
	if resp.status != http.StatusCreated {
		t.Fatalf("登録 = %d, want 201: %s", resp.status, resp.body)
	}
	var created struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(resp.body, &created); err != nil || created.ID == "" {
		t.Fatalf("登録の本文 = %s", resp.body)
	}
	return created.ID, family.IDToken
}

func startNow(t *testing.T, backend, path, idToken string) string {
	t.Helper()
	resp := postJSON(t, backend, path, "Bearer "+idToken, `{"message": "金曜の通院", "script": "ハナさん、美咲さんからです。"}`)
	if resp.status != http.StatusCreated {
		t.Fatalf("今すぐ通話 %s = %d, want 201: %s", path, resp.status, resp.body)
	}
	var started struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(resp.body, &started); err != nil || started.ID == "" {
		t.Fatalf("今すぐ通話の本文 = %s", resp.body)
	}
	return started.ID
}

func callState(t *testing.T, personID, callID string) string {
	t.Helper()
	doc, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Doc(callID).Get(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	state, _ := doc.Data()["state"].(string)
	return state
}

func sendPhoneState(t *testing.T, conn *websocket.Conn, callID, state string) {
	t.Helper()
	body, err := json.Marshal(protocol.PhoneMessage{
		Type:   protocol.PhoneTypeState,
		CallID: callID,
		State:  state,
	})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := conn.Write(ctx, websocket.MessageText, body); err != nil {
		t.Fatal(err)
	}
}

func stayCallState(t *testing.T, personID, callID, want string, window time.Duration) {
	t.Helper()
	deadline := time.Now().Add(window)
	for time.Now().Before(deadline) {
		if got := callState(t, personID, callID); got != want {
			t.Fatalf("状態 = %s, want %s", got, want)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func waitCallState(t *testing.T, personID, callID, want string) {
	t.Helper()
	deadline := time.Now().Add(slowEmulatorBound)
	var got string
	for {
		got = callState(t, personID, callID)
		if got == want {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("状態 = %s, want %s", got, want)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func waitConnected(t *testing.T, handler *server.Handler, personID string, want bool) {
	t.Helper()
	deadline := time.Now().Add(slowEmulatorBound)
	for handler.Connected(personID) != want {
		if time.Now().After(deadline) {
			t.Fatalf("%s の接続 = %v, want %v", personID, handler.Connected(personID), want)
		}
		time.Sleep(time.Millisecond)
	}
}

func dialPhone(t *testing.T, backend, person, secret string) *websocket.Conn {
	t.Helper()
	u, err := url.Parse(backend)
	if err != nil {
		t.Fatal(err)
	}
	u.Scheme = "ws"
	u.Path = protocol.PhonePath
	u.RawQuery = url.Values{"watchedPerson": {person}}.Encode()
	header := http.Header{}
	header.Set(protocol.PhoneSecretHeader, secret)
	conn, _, err := websocket.Dial(t.Context(), u.String(), &websocket.DialOptions{HTTPHeader: header})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.CloseNow() })
	return conn
}

func readPhone(conn *websocket.Conn) {
	go func() {
		for {
			if _, _, err := conn.Read(context.Background()); err != nil {
				return
			}
		}
	}()
}

func call(t *testing.T, backend, method, path, secret, body string) response {
	t.Helper()
	var reader io.Reader
	if body != "" {
		reader = strings.NewReader(body)
	}
	req, err := http.NewRequestWithContext(t.Context(), method, backend+path, reader)
	if err != nil {
		t.Fatal(err)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if secret != "" {
		req.Header.Set(protocol.PhoneSecretHeader, secret)
	}
	got, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer got.Body.Close()
	data, err := io.ReadAll(got.Body)
	if err != nil {
		t.Fatal(err)
	}
	return response{status: got.StatusCode, body: data, header: got.Header}
}

func options(t *testing.T, backend, path, origin string) response {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), http.MethodOptions, backend+path, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Origin", origin)
	req.Header.Set("Access-Control-Request-Method", "POST")
	req.Header.Set("Access-Control-Request-Headers", "authorization, content-type")
	got, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer got.Body.Close()
	data, err := io.ReadAll(got.Body)
	if err != nil {
		t.Fatal(err)
	}
	return response{status: got.StatusCode, body: data, header: got.Header}
}
