package server_test

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/coder/websocket"
	"google.golang.org/genai"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/clock"
	"github.com/gesop0n/kazokuai/internal/clock/clocktest"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

func TestRegisterPhone(t *testing.T) {
	when := time.Date(2026, 11, 10, 1, 2, 3, 0, time.UTC)
	clock := clocktest.New(when)
	srv := newDemoServer(t, "demo-kazokuai", protocol.DevPhoneSecret, clock)

	t.Run("ID と鍵と合言葉で登録すると、鍵そのものは残さず成功する", func(t *testing.T) {
		id := testPhoneID(t)
		const key = "alpha-key"
		resp := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, key)
		if resp.status != http.StatusCreated {
			t.Fatalf("ステータス = %d, want 201: %s", resp.status, resp.body)
		}
		var created struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(resp.body, &created); err != nil || created.ID != id {
			t.Fatalf("返した本文 = %s, want %s", resp.body, id)
		}
		data := phoneDoc(t, id)
		if data["watchedPersonId"] != "" {
			t.Fatalf("見守る方 = %v, want 空", data["watchedPersonId"])
		}
		registeredAt, _ := data["registeredAt"].(time.Time)
		if !registeredAt.Equal(when) {
			t.Fatalf("登録した時刻 = %v, want %v", data["registeredAt"], when)
		}
		assertKeyHidden(t, data, key)
	})

	t.Run("同じ ID と鍵でもう一度登録しても成功し、結び付きと登録した時刻は残る", func(t *testing.T) {
		id := testPhoneID(t)
		const key = "alpha-key"
		first := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, key)
		if first.status != http.StatusCreated {
			t.Fatalf("最初の登録 = %d, want 201: %s", first.status, first.body)
		}
		personID := id + "-person"
		if _, err := emulators.Firestore.Collection("phones").Doc(id).Update(t.Context(), []firestore.Update{
			{Path: "watchedPersonId", Value: personID},
		}); err != nil {
			t.Fatal(err)
		}
		clock.Advance(time.Hour)

		again := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, key)
		if again.status != http.StatusOK {
			t.Fatalf("登録し直し = %d, want 200: %s", again.status, again.body)
		}
		data := phoneDoc(t, id)
		if data["watchedPersonId"] != personID {
			t.Fatalf("見守る方 = %v, want %s", data["watchedPersonId"], personID)
		}
		registeredAt, _ := data["registeredAt"].(time.Time)
		if !registeredAt.Equal(when) {
			t.Fatalf("登録した時刻 = %v, want %v", data["registeredAt"], when)
		}
	})

	t.Run("同じ ID で鍵が違う登録は断り、残してある鍵は変えない", func(t *testing.T) {
		id := testPhoneID(t)
		const key = "alpha-key"
		if resp := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, key); resp.status != http.StatusCreated {
			t.Fatalf("最初の登録 = %d, want 201: %s", resp.status, resp.body)
		}
		before := phoneDoc(t, id)

		resp := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, "beta-key")
		if resp.status != http.StatusConflict || !strings.Contains(string(resp.body), protocol.PhoneAnswerBadKey) {
			t.Fatalf("登録 = %d %s, want 409 %s", resp.status, resp.body, protocol.PhoneAnswerBadKey)
		}
		after := phoneDoc(t, id)
		if after["keyHash"] != before["keyHash"] || after["watchedPersonId"] != before["watchedPersonId"] {
			t.Fatalf("断ったあとの電話機 = %v, want %v", after, before)
		}
		registeredAt, _ := after["registeredAt"].(time.Time)
		beforeAt, _ := before["registeredAt"].(time.Time)
		if !registeredAt.Equal(beforeAt) {
			t.Fatalf("登録した時刻 = %v, want %v", registeredAt, beforeAt)
		}
	})

	t.Run("合言葉が無い登録は断る", func(t *testing.T) {
		for _, secret := range []string{"", "other-secret"} {
			id := testPhoneID(t) + secret
			resp := registerPhone(t, srv.URL, secret, id, "alpha-key")
			if resp.status != http.StatusUnauthorized || !strings.Contains(string(resp.body), protocol.PhoneAnswerBadSecret) {
				t.Errorf("合言葉 %q = %d %s, want 401 %s", secret, resp.status, resp.body, protocol.PhoneAnswerBadSecret)
			}
			_, err := emulators.Firestore.Collection("phones").Doc(id).Get(t.Context())
			if status.Code(err) != codes.NotFound {
				t.Errorf("合言葉 %q で電話機が残った: %v", secret, err)
			}
		}
	})

	t.Run("登録の道は /api の下にない", func(t *testing.T) {
		resp := registerPhoneAt(t, srv.URL, "/api"+protocol.PhoneRegisterPath, protocol.DevPhoneSecret, testPhoneID(t), "alpha-key")
		if resp.status != http.StatusNotFound {
			t.Fatalf("ステータス = %d, want 404: %s", resp.status, resp.body)
		}
	})
}

func TestPhoneKeyAnswersDifferFromUnknownPhone(t *testing.T) {
	srv := newDemoServer(t, "demo-kazokuai", protocol.DevPhoneSecret, nil)
	id := testPhoneID(t)
	const key = "alpha-key"
	if resp := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, key); resp.status != http.StatusCreated {
		t.Fatalf("登録 = %d, want 201: %s", resp.status, resp.body)
	}

	for _, target := range []struct{ method, path, body string }{
		{http.MethodPost, protocol.TokenPath, `{"callId":"call-1","watchedPersonId":"someone"}`},
		{http.MethodPost, protocol.CallReportPath, `{"callId":"call-1","watchedPersonId":"someone","utterances":[]}`},
		{http.MethodGet, protocol.PhonePath, ""},
	} {
		unknown := callPhone(t, srv.URL, target.method, target.path, "missing-phone", key, target.body)
		if unknown.status != http.StatusNotFound || !strings.Contains(string(unknown.body), protocol.PhoneAnswerUnknownPhone) {
			t.Errorf("%s %s の知らない ID = %d %s, want 404 %s", target.method, target.path, unknown.status, unknown.body, protocol.PhoneAnswerUnknownPhone)
		}
		if strings.Contains(string(unknown.body), protocol.PhoneAnswerBadKey) {
			t.Errorf("%s %s は知らない ID を、鍵が違うと答えた: %s", target.method, target.path, unknown.body)
		}

		wrong := callPhone(t, srv.URL, target.method, target.path, id, "beta-key", target.body)
		if wrong.status != http.StatusUnauthorized || !strings.Contains(string(wrong.body), protocol.PhoneAnswerBadKey) {
			t.Errorf("%s %s の違う鍵 = %d %s, want 401 %s", target.method, target.path, wrong.status, wrong.body, protocol.PhoneAnswerBadKey)
		}
		if strings.Contains(string(wrong.body), protocol.PhoneAnswerUnknownPhone) {
			t.Errorf("%s %s は違う鍵を、知らない ID と答えた: %s", target.method, target.path, wrong.body)
		}
	}
}

func TestLinkedPhoneGetsTheCallWithItsKey(t *testing.T) {
	srv, handler := newAuthServer(t, clock.Real{})
	personID, familyToken := registerHanako(t, srv.URL)
	id := testPhoneID(t)
	const key = "alpha-key"
	if resp := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, key); resp.status != http.StatusCreated {
		t.Fatalf("登録 = %d, want 201: %s", resp.status, resp.body)
	}

	conn := dialPhoneKey(t, srv.URL, id, key)
	calls := readPhoneCalls(conn)
	if _, err := emulators.Firestore.Collection("phones").Doc(id).Update(t.Context(), []firestore.Update{
		{Path: "watchedPersonId", Value: personID},
	}); err != nil {
		t.Fatal(err)
	}
	waitConnected(t, handler, personID, true)

	callID := startNow(t, srv.URL, protocol.StartCallPath, familyToken)
	select {
	case got := <-calls:
		if got.CallID != callID {
			t.Fatalf("届いた電話 = %s, want %s", got.CallID, callID)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("結び付いた電話機に今すぐ通話が来なかった")
	}

	tokenBody, err := json.Marshal(protocol.TokenRequest{CallID: callID})
	if err != nil {
		t.Fatal(err)
	}
	token := callPhone(t, srv.URL, http.MethodPost, protocol.TokenPath, id, key, string(tokenBody))
	if token.status != http.StatusOK {
		t.Fatalf("トークン = %d, want 200: %s", token.status, token.body)
	}
	var issued struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(token.body, &issued); err != nil || issued.Token != "auth_tokens/1" {
		t.Fatalf("トークンの本文 = %s, want auth_tokens/1", token.body)
	}

	reportBody, err := json.Marshal(protocol.CallReport{
		CallID:     callID,
		StartedAt:  time.Date(2026, 11, 10, 1, 0, 0, 0, time.UTC),
		DurationMs: 1200,
		Utterances: []protocol.Utterance{{
			Speaker:  protocol.SpeakerAI,
			OffsetMs: 100,
			Text:     "こんにちは",
		}},
	})
	if err != nil {
		t.Fatal(err)
	}
	report := callPhone(t, srv.URL, http.MethodPost, protocol.CallReportPath, id, key, string(reportBody))
	if report.status != http.StatusAccepted {
		t.Fatalf("報告 = %d, want 202: %s", report.status, report.body)
	}
	text := utteranceText(t, personID, callID)
	if text != "こんにちは" {
		t.Fatalf("保存した発話 = %q, want こんにちは", text)
	}
}

func TestUnlinkedPhoneStaysConnectedAndGetsNoCall(t *testing.T) {
	srv, handler := newAuthServer(t, clock.Real{})
	personID, familyToken := registerHanako(t, srv.URL)
	id := testPhoneID(t)
	const key = "alpha-key"
	if resp := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, key); resp.status != http.StatusCreated {
		t.Fatalf("登録 = %d, want 201: %s", resp.status, resp.body)
	}

	conn := dialPhoneKey(t, srv.URL, id, key)
	calls, closed := watchPhone(conn)

	resp := postJSON(t, srv.URL, protocol.StartCallPath, "Bearer "+familyToken, `{"message": "金曜の通院", "script": "ハナさん、美咲さんからです。"}`)
	if resp.status != http.StatusConflict || !strings.Contains(string(resp.body), protocol.PhoneNotConnected) {
		t.Fatalf("今すぐ通話 = %d %s, want 409 %s", resp.status, resp.body, protocol.PhoneNotConnected)
	}
	if handler.Connected(personID) {
		t.Fatal("結び付きのない電話機を、見守る方の電話機として扱った")
	}
	select {
	case got := <-calls:
		t.Fatalf("電話が来た: %+v", got)
	case <-closed:
		t.Fatal("同期していない電話機の接続が切れた")
	case <-time.After(200 * time.Millisecond):
	}

	for _, path := range []string{protocol.TokenPath, protocol.CallReportPath} {
		body := `{"callId":"call-1"}`
		if path == protocol.CallReportPath {
			body = `{"callId":"call-1","utterances":[]}`
		}
		resp = callPhone(t, srv.URL, http.MethodPost, path, id, key, body)
		if resp.status != http.StatusConflict || !strings.Contains(string(resp.body), "この電話機は同期していません") {
			t.Errorf("%s = %d %s, want 409 同期していない", path, resp.status, resp.body)
		}
		if strings.Contains(string(resp.body), "見守る方の ID") {
			t.Errorf("%s が、見守る方の ID をリクエストに入れるよう求めた: %s", path, resp.body)
		}
	}
}

func TestPhoneThatNamesAnotherPersonIsRefused(t *testing.T) {
	srv := newAuthServerOnly(t, clock.Real{})
	personID, _ := registerHanako(t, srv.URL)
	id := testPhoneID(t)
	const key = "alpha-key"
	if resp := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, key); resp.status != http.StatusCreated {
		t.Fatalf("登録 = %d, want 201: %s", resp.status, resp.body)
	}
	if _, err := emulators.Firestore.Collection("phones").Doc(id).Update(t.Context(), []firestore.Update{
		{Path: "watchedPersonId", Value: personID},
	}); err != nil {
		t.Fatal(err)
	}

	t.Run("クエリで見守る方を名乗ると、結び付きと同じでも断る", func(t *testing.T) {
		for _, named := range []string{personID, personID + "-other"} {
			resp := callPhone(t, srv.URL, http.MethodGet, protocol.PhonePath+"?watchedPerson="+url.QueryEscape(named), id, key, "")
			if resp.status != http.StatusBadRequest || !strings.Contains(string(resp.body), "見守る方は結び付きから決まります") {
				t.Errorf("クエリ %s = %d %s, want 400", named, resp.status, resp.body)
			}
		}
		conn := dialPhoneKey(t, srv.URL, id, key)
		conn.CloseNow()
	})

	t.Run("本文で別の見守る方を名乗ると、トークンも報告も断る", func(t *testing.T) {
		other := personID + "-other"
		targets := []struct{ path, body string }{
			{protocol.TokenPath, `{"callId":"call-1","watchedPersonId":"` + other + `"}`},
			{protocol.CallReportPath, `{"callId":"call-1","watchedPersonId":"` + other + `","utterances":[]}`},
		}
		for _, target := range targets {
			resp := callPhone(t, srv.URL, http.MethodPost, target.path, id, key, target.body)
			if resp.status != http.StatusForbidden || !strings.Contains(string(resp.body), protocol.PhoneAnswerOtherPerson) {
				t.Errorf("POST %s = %d %s, want 403 %s", target.path, resp.status, resp.body, protocol.PhoneAnswerOtherPerson)
			}
		}
	})
}

func TestPhoneKeyConnectionLogsTheLinkedPerson(t *testing.T) {
	const secret = "phone-secret-do-not-log"
	const key = "alpha-key"
	var logs lockedBuffer
	logger := log.New(&logs, "", log.LstdFlags)
	srv, handler := newLoggingServer(t, secret, logger, nil)
	person, token := registerHanako(t, srv.URL)
	id := testPhoneID(t)
	if resp := registerPhone(t, srv.URL, secret, id, key); resp.status != http.StatusCreated {
		t.Fatalf("登録 = %d %s", resp.status, resp.body)
	}
	if _, err := emulators.Firestore.Collection("phones").Doc(id).Update(t.Context(), []firestore.Update{
		{Path: "watchedPersonId", Value: person},
	}); err != nil {
		t.Fatal(err)
	}

	conn := dialPhoneKey(t, srv.URL, id, key)
	readPhone(conn)
	waitConnected(t, handler, person, true)
	waitForLog(t, &logs, "電話機がつながりました。見守る方: "+person)
	if strings.Contains(logs.String(), secret) || strings.Contains(logs.String(), key) {
		t.Fatal("つながったログに合言葉か鍵がある")
	}

	if err := conn.Close(websocket.StatusNormalClosure, "切った-"+secret); err != nil {
		t.Fatal(err)
	}
	waitConnected(t, handler, person, false)
	waitForLog(t, &logs, "電話機が切れました。見守る方: "+person)
	waitForLog(t, &logs, "理由: 切った-[合言葉]")
	if strings.Contains(logs.String(), secret) || strings.Contains(logs.String(), key) {
		t.Fatal("切れたログに合言葉か鍵がある")
	}

	resp := postJSON(t, srv.URL, "/calls/now", "Bearer "+token, `{"message": "金曜の通院", "script": "ハナさん、美咲さんからです。"}`)
	if resp.status != http.StatusConflict || !strings.Contains(string(resp.body), protocol.PhoneNotConnected) {
		t.Fatalf("今すぐ通話 = %d %s, want 409 phone_not_connected", resp.status, resp.body)
	}
	waitForLog(t, &logs, "今すぐ通話を断りました。電話機がつながっていません。見守る方: "+person)
	if strings.Contains(logs.String(), secret) || strings.Contains(logs.String(), key) {
		t.Fatal("断ったログに合言葉か鍵がある")
	}
}

// phoneIDs は、1 回のテスト実行のあいだ同じ電話機の ID を返す。
var phoneIDs sync.Map

// testPhoneID は、このテスト実行だけの電話機の ID を返す。同じ t では同じ ID である。
// 名前だけにすると、go test -count が同じエミュレーターへ同じ ID を重ね、2 回目の登録が 200 になる。
func testPhoneID(t *testing.T) string {
	t.Helper()
	if id, ok := phoneIDs.Load(t); ok {
		return id.(string)
	}
	var nonce [4]byte
	if _, err := rand.Read(nonce[:]); err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(append([]byte(t.Name()), nonce[:]...))
	id := "phone-" + hex.EncodeToString(sum[:6])
	actual, loaded := phoneIDs.LoadOrStore(t, id)
	if loaded {
		return actual.(string)
	}
	t.Cleanup(func() { phoneIDs.Delete(t) })
	return id
}

func registerPhone(t *testing.T, backend, secret, id, key string) response {
	t.Helper()
	return registerPhoneAt(t, backend, protocol.PhoneRegisterPath, secret, id, key)
}

func registerPhoneAt(t *testing.T, backend, path, secret, id, key string) response {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, backend+path, nil)
	if err != nil {
		t.Fatal(err)
	}
	if secret != "" {
		req.Header.Set(protocol.PhoneSecretHeader, secret)
	}
	req.Header.Set(protocol.PhoneIDHeader, id)
	req.Header.Set(protocol.PhoneKeyHeader, key)
	return doRequest(t, req)
}

func callPhone(t *testing.T, backend, method, path, id, key, body string) response {
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
	req.Header.Set(protocol.PhoneIDHeader, id)
	req.Header.Set(protocol.PhoneKeyHeader, key)
	return doRequest(t, req)
}

func doRequest(t *testing.T, req *http.Request) response {
	t.Helper()
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

func phoneDoc(t *testing.T, id string) map[string]any {
	t.Helper()
	doc, err := emulators.Firestore.Collection("phones").Doc(id).Get(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	return doc.Data()
}

func assertKeyHidden(t *testing.T, data map[string]any, key string) {
	t.Helper()
	hash, _ := data["keyHash"].(string)
	if hash == "" || hash == key || strings.Contains(hash, key) {
		t.Fatalf("鍵のハッシュ = %q", hash)
	}
	for name, value := range data {
		if text, ok := value.(string); ok && text == key {
			t.Fatalf("%s に鍵がある", name)
		}
	}
}

func dialPhoneKey(t *testing.T, backend, id, key string) *websocket.Conn {
	t.Helper()
	u, err := url.Parse(backend)
	if err != nil {
		t.Fatal(err)
	}
	u.Scheme = "ws"
	u.Path = protocol.PhonePath
	header := http.Header{}
	header.Set(protocol.PhoneIDHeader, id)
	header.Set(protocol.PhoneKeyHeader, key)
	conn, _, err := websocket.Dial(t.Context(), u.String(), &websocket.DialOptions{HTTPHeader: header})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.CloseNow() })
	return conn
}

func readPhoneCalls(conn *websocket.Conn) <-chan protocol.PhoneMessage {
	calls, _ := watchPhone(conn)
	return calls
}

// watchPhone は、接続に届いた電話と、接続が切れたことを返す。読むのは 1 つだけである。
func watchPhone(conn *websocket.Conn) (<-chan protocol.PhoneMessage, <-chan struct{}) {
	calls := make(chan protocol.PhoneMessage, 1)
	closed := make(chan struct{})
	go func() {
		defer close(closed)
		for {
			_, data, err := conn.Read(context.Background())
			if err != nil {
				return
			}
			var msg protocol.PhoneMessage
			if json.Unmarshal(data, &msg) != nil || msg.Type != protocol.PhoneTypeCall {
				continue
			}
			calls <- msg
		}
	}()
	return calls, closed
}

type stubTokens struct{}

func (stubTokens) Create(context.Context, *genai.CreateAuthTokenConfig) (*genai.AuthToken, error) {
	return &genai.AuthToken{Name: "auth_tokens/1"}, nil
}

func newAuthServer(t *testing.T, clk clock.Clock) (*httptest.Server, *server.Handler) {
	t.Helper()
	handler := server.New(server.Config{
		ProjectID:    "demo-kazokuai",
		PhoneSecret:  protocol.DevPhoneSecret,
		Model:        "gemini-test",
		Voice:        "Kore",
		RingTimeout:  time.Minute,
		MaxCall:      5 * time.Minute,
		WrapUpBefore: 30 * time.Second,
		TokenMargin:  time.Minute,
	}, emulators, stubTokens{}, nil, clk)
	srv := httptest.NewServer(handler)
	t.Cleanup(func() {
		handler.Stop()
		srv.Close()
	})
	return srv, handler
}

func newAuthServerOnly(t *testing.T, clk clock.Clock) *httptest.Server {
	t.Helper()
	srv, _ := newAuthServer(t, clk)
	return srv
}

func TestPhoneHearsTheLinkThatExistsWhenItFinishesConnecting(t *testing.T) {
	t.Run("つないでいるあいだに同期が終わると、最後に同期したと知らせる", func(t *testing.T) {
		srv, logs, release := newPausedPhoneServer(t)
		family := signUp(t)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)

		conn := dialPhoneKey(t, srv.URL, id, syncPhoneKey)
		waitUntilEntered(t, release.entered)
		msgs := collectMessages(t, conn)
		linkPhoneWithCode(t, srv.URL, family.IDToken, id)
		release.letGo()
		waitForLog(t, logs, "電話機がつながりました")

		if got := lastSyncNotice(t, msgs); got != protocol.PhoneTypeSynced {
			t.Fatalf("最後の状態 = %s, want %s", got, protocol.PhoneTypeSynced)
		}
	})

	t.Run("つないでいるあいだに別の電話機へ替わると、最後に同期していないと知らせる", func(t *testing.T) {
		srv, logs, release := newPausedPhoneServer(t)
		family := signUp(t)
		firstID := testPhoneID(t) + "-a"
		secondID := testPhoneID(t) + "-b"
		registerKeyedPhone(t, srv.URL, firstID)
		linkPhoneWithCode(t, srv.URL, family.IDToken, firstID)

		conn := dialPhoneKey(t, srv.URL, firstID, syncPhoneKey)
		waitUntilEntered(t, release.entered)
		msgs := collectMessages(t, conn)
		registerKeyedPhone(t, srv.URL, secondID)
		linkPhoneWithCode(t, srv.URL, family.IDToken, secondID)
		release.letGo()
		waitForLog(t, logs, "電話機がつながりました")

		if got := lastSyncNotice(t, msgs); got != protocol.PhoneTypeNotSynced {
			t.Fatalf("最後の状態 = %s, want %s", got, protocol.PhoneTypeNotSynced)
		}
	})
}

// 結び付きの読み取りが失敗したときは、未同期とは知らせずに接続を閉じる。
// そのあと読み直せば、切れていた電話はつながらなかったにならない。
func TestFailedLinkReadClosesAndTheNextConnectionKeepsTheCall(t *testing.T) {
	clk := clocktest.New(time.Date(2026, 1, 2, 9, 0, 0, 0, time.UTC))
	srv, handler := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
	person, token := registerHanako(t, srv.URL)
	conn := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
	readPhone(conn)
	waitConnected(t, handler, person, true)
	callID := startNow(t, srv.URL, protocol.StartCallPath, token)

	conn.CloseNow()
	waitConnected(t, handler, person, false)

	server.StubPhonePersonRead(func(context.Context, *firestore.DocumentRef) (*firestore.DocumentSnapshot, error) {
		return nil, errors.New("一時的に読めない")
	})
	t.Cleanup(func() { server.StubPhonePersonRead(nil) })

	failed := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
	msgs := collectMessages(t, failed)
	select {
	case msg, ok := <-msgs:
		if ok {
			t.Fatalf("読めないあいだに %s が届いた", msg.Type)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("結び付きを読めなくても接続を閉じなかった")
	}
	waitConnected(t, handler, person, false)
	if got := callState(t, person, callID); got != protocol.StateRinging {
		t.Fatalf("読めないあいだの状態 = %s, want 呼び出し中", got)
	}

	server.StubPhonePersonRead(nil)
	again := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
	readPhone(again)
	waitConnected(t, handler, person, true)
	clk.Advance(protocol.ReconnectGrace)
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		if got := callState(t, person, callID); got != protocol.StateRinging {
			t.Fatalf("読み直せたのに状態 = %s", got)
		}
		time.Sleep(20 * time.Millisecond)
	}
	sendPhoneState(t, again, callID, protocol.StateTalking)
	waitCallState(t, person, callID, protocol.StateTalking)
}

// phonePause は、最初の電話機の接続を登録したあと、結び付きを読む前に止める。
type phonePause struct {
	entered chan struct{}
	letGo   func()
}

func newPausedPhoneServer(t *testing.T) (*httptest.Server, *lockedBuffer, phonePause) {
	t.Helper()
	entered := make(chan struct{})
	release := make(chan struct{})
	var once sync.Once
	var releaseOnce sync.Once
	pause := phonePause{
		entered: entered,
		letGo: func() {
			releaseOnce.Do(func() { close(release) })
		},
	}
	t.Cleanup(pause.letGo)
	var logs lockedBuffer
	handler := server.New(server.Config{
		ProjectID:   "demo-kazokuai",
		PhoneSecret: protocol.DevPhoneSecret,
		Logger:      log.New(&logs, "", 0),
		AfterPhoneRegistered: func() {
			once.Do(func() {
				close(entered)
				<-release
			})
		},
	}, emulators, nil, nil, clock.Real{})
	srv := httptest.NewServer(handler)
	t.Cleanup(func() {
		handler.Stop()
		srv.Close()
	})
	return srv, &logs, pause
}

func waitUntilEntered(t *testing.T, entered <-chan struct{}) {
	t.Helper()
	select {
	case <-entered:
	case <-time.After(2 * time.Second):
		t.Fatal("接続を登録する前に止まった")
	}
}

func lastSyncNotice(t *testing.T, msgs <-chan protocol.PhoneMessage) string {
	t.Helper()
	var last string
	deadline := time.NewTimer(2 * time.Second)
	defer deadline.Stop()
	var idle *time.Timer
	defer func() {
		if idle != nil {
			idle.Stop()
		}
	}()
	for {
		var idleC <-chan time.Time
		if idle != nil {
			idleC = idle.C
		}
		select {
		case msg, ok := <-msgs:
			if !ok {
				t.Fatal("接続が切れた")
			}
			if msg.Type != protocol.PhoneTypeSynced && msg.Type != protocol.PhoneTypeNotSynced {
				continue
			}
			last = msg.Type
			if idle == nil {
				idle = time.NewTimer(200 * time.Millisecond)
				continue
			}
			if !idle.Stop() {
				select {
				case <-idle.C:
				default:
				}
			}
			idle.Reset(200 * time.Millisecond)
		case <-idleC:
			return last
		case <-deadline.C:
			t.Fatalf("同期の状態が届かなかった。最後 = %q", last)
		}
	}
}

func utteranceText(t *testing.T, personID, callID string) string {
	t.Helper()
	docs, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Doc(callID).Collection("utterances").Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(docs) != 1 {
		t.Fatalf("発話 = %d 件, want 1", len(docs))
	}
	text, _ := docs[0].Data()["text"].(string)
	return text
}
