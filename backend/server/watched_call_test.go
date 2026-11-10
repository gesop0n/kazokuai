package server_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/clock"
	"github.com/gesop0n/kazokuai/internal/clock/clocktest"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

func TestWatchedPersonStartsACall(t *testing.T) {
	const key = "alpha-key"
	const wantScript = "ハナさんと呼びかけて、かぞくAIであることを伝えてください。何を話したいかを尋ねてから、話し相手として話してください。"
	tokens := &recordTokens{}
	srv := newWatchedCallServer(t, tokens)

	t.Run("同期済みの電話機は、空の伝えたいことと始めの通話内容と、見守る方から始めた印で電話を作る", func(t *testing.T) {
		personID, id := linkHanakoPhone(t, srv.URL, key)

		resp := callPhone(t, srv.URL, http.MethodPost, protocol.PhoneCallPath, id, key, "")
		if resp.status != http.StatusCreated {
			t.Fatalf("ステータス = %d, want 201: %s", resp.status, resp.body)
		}
		var started protocol.StartedCall
		if err := json.Unmarshal(resp.body, &started); err != nil || started.ID == "" {
			t.Fatalf("返した本文 = %s, want 電話の ID", resp.body)
		}
		data := callDoc(t, personID, started.ID)
		if data["state"] != protocol.StateRinging {
			t.Fatalf("状態 = %v, want %s", data["state"], protocol.StateRinging)
		}
		if data["message"] != "" {
			t.Fatalf("伝えたいこと = %v, want 空", data["message"])
		}
		if data["script"] != wantScript {
			t.Fatalf("通話内容 = %v, want %s", data["script"], wantScript)
		}
		if data[protocol.CallStartedByWatchedPerson] != true {
			t.Fatalf("見守る方から始めた印 = %v, want true", data[protocol.CallStartedByWatchedPerson])
		}

		tokenResp := callPhone(t, srv.URL, http.MethodPost, protocol.TokenPath, id, key, `{"callId":"`+started.ID+`"}`)
		if tokenResp.status != http.StatusOK {
			t.Fatalf("トークン = %d, want 200: %s", tokenResp.status, tokenResp.body)
		}
		var token protocol.TokenResponse
		if err := json.Unmarshal(tokenResp.body, &token); err != nil {
			t.Fatal(err)
		}
		if token.Times.MaxCall != 5*time.Minute {
			t.Fatalf("電話の長さ = %s, want 5 分", token.Times.MaxCall)
		}
		instruction := instructionText(t, tokens.last())
		for _, want := range []string{"ハナさん", "かぞくAI", "何を話したいか", "話し相手"} {
			if !strings.Contains(instruction, want) {
				t.Errorf("システム指示に %q がない:\n%s", want, instruction)
			}
		}
		for _, avoid := range []string{"その言葉のまま", "ご家族に頼まれて"} {
			if strings.Contains(instruction, avoid) {
				t.Errorf("システム指示に %q がある:\n%s", avoid, instruction)
			}
		}

		talking := callPhone(t, srv.URL, http.MethodPost, protocol.PhoneCallPath, id, key, "")
		if talking.status != http.StatusConflict || !strings.Contains(string(talking.body), protocol.CallInProgress) {
			t.Fatalf("呼び出し中 = %d %s, want 409 %s", talking.status, talking.body, protocol.CallInProgress)
		}
		if _, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Doc(started.ID).Update(t.Context(), []firestore.Update{
			{Path: "state", Value: protocol.StateTalking},
		}); err != nil {
			t.Fatal(err)
		}
		again := callPhone(t, srv.URL, http.MethodPost, protocol.PhoneCallPath, id, key, "")
		if again.status != http.StatusConflict || !strings.Contains(string(again.body), protocol.CallInProgress) {
			t.Fatalf("通話中 = %d %s, want 409 %s", again.status, again.body, protocol.CallInProgress)
		}
		if got := len(personCallDocs(t, personID)); got != 1 {
			t.Fatalf("電話の数 = %d, want 1", got)
		}
	})

	t.Run("同期していない電話機は断られ、電話を作らない", func(t *testing.T) {
		id := testPhoneID(t)
		if resp := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, key); resp.status != http.StatusCreated {
			t.Fatalf("登録 = %d, want 201: %s", resp.status, resp.body)
		}
		resp := callPhone(t, srv.URL, http.MethodPost, protocol.PhoneCallPath, id, key, "")
		if resp.status != http.StatusConflict || !strings.Contains(string(resp.body), protocol.PhoneNotSynced) {
			t.Fatalf("ステータス = %d %s, want 409 %s", resp.status, resp.body, protocol.PhoneNotSynced)
		}
	})

	t.Run("違う鍵は断られ、電話を作らない", func(t *testing.T) {
		personID, id := linkHanakoPhone(t, srv.URL, key)
		resp := callPhone(t, srv.URL, http.MethodPost, protocol.PhoneCallPath, id, "beta-key", "")
		if resp.status != http.StatusUnauthorized || !strings.Contains(string(resp.body), protocol.PhoneAnswerBadKey) {
			t.Fatalf("ステータス = %d %s, want 401 %s", resp.status, resp.body, protocol.PhoneAnswerBadKey)
		}
		if got := len(personCallDocs(t, personID)); got != 0 {
			t.Fatalf("電話の数 = %d, want 0", got)
		}
	})

	t.Run("道は /api の下にない", func(t *testing.T) {
		_, id := linkHanakoPhone(t, srv.URL, key)
		resp := callPhone(t, srv.URL, http.MethodPost, "/api"+protocol.PhoneCallPath, id, key, "")
		if resp.status != http.StatusNotFound {
			t.Fatalf("ステータス = %d, want 404: %s", resp.status, resp.body)
		}
	})
}

func TestLostStarResponseExpiresAndAllowsAnotherCall(t *testing.T) {
	const key = "alpha-key"
	start := time.Date(2026, 11, 10, 9, 0, 0, 0, time.UTC)
	clk := clocktest.New(start)
	srv, handler := newWatchedCallServerOn(t, stubTokens{}, clk)
	personID, idToken := registerHanako(t, srv.URL)
	id := testPhoneID(t)
	if resp := registerPhone(t, srv.URL, protocol.DevPhoneSecret, id, key); resp.status != http.StatusCreated {
		t.Fatalf("登録 = %d, want 201: %s", resp.status, resp.body)
	}
	if _, err := emulators.Firestore.Collection("phones").Doc(id).Update(t.Context(), []firestore.Update{
		{Path: "watchedPersonId", Value: personID},
	}); err != nil {
		t.Fatal(err)
	}
	conn := dialPhoneKey(t, srv.URL, id, key)
	readPhoneCalls(conn)
	waitConnected(t, handler, personID, true)

	postLost(t, srv.URL, id, key)
	lostID := onlyCallID(t, personID)
	if got := callState(t, personID, lostID); got != protocol.StateRinging {
		t.Fatalf("失った直後の状態 = %s, want %s", got, protocol.StateRinging)
	}
	assertCallInProgress(t, srv.URL, id, key, idToken)

	clk.WaitForDeadline(start.Add(time.Minute))
	clk.Advance(time.Minute - time.Millisecond)
	if got := callState(t, personID, lostID); got != protocol.StateRinging {
		t.Fatalf("上限の直前の状態 = %s, want %s", got, protocol.StateRinging)
	}
	assertCallInProgress(t, srv.URL, id, key, idToken)

	clk.Advance(time.Millisecond)
	waitUntilCallState(t, personID, lostID, protocol.StateFailed)
	assertCallInProgressGone(t, srv.URL, id, key, idToken, personID)
}

func TestTalkingWatchedCallStaysPastTheRingLimit(t *testing.T) {
	const key = "alpha-key"
	start := time.Date(2026, 11, 10, 9, 0, 0, 0, time.UTC)
	clk := clocktest.New(start)
	srv, _ := newWatchedCallServerOn(t, stubTokens{}, clk)
	personID, id := linkHanakoPhone(t, srv.URL, key)

	resp := callPhone(t, srv.URL, http.MethodPost, protocol.PhoneCallPath, id, key, "")
	if resp.status != http.StatusCreated {
		t.Fatalf("ステータス = %d, want 201: %s", resp.status, resp.body)
	}
	var started protocol.StartedCall
	if err := json.Unmarshal(resp.body, &started); err != nil || started.ID == "" {
		t.Fatalf("返した本文 = %s, want 電話の ID", resp.body)
	}
	if _, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Doc(started.ID).Update(t.Context(), []firestore.Update{
		{Path: "state", Value: protocol.StateTalking},
	}); err != nil {
		t.Fatal(err)
	}
	clk.WaitForDeadline(start.Add(time.Minute))
	clk.Advance(time.Minute)
	stayCallState(t, personID, started.ID, protocol.StateTalking, time.Second)
}

func assertCallInProgress(t *testing.T, backend, id, key, idToken string) {
	t.Helper()
	again := callPhone(t, backend, http.MethodPost, protocol.PhoneCallPath, id, key, "")
	if again.status != http.StatusConflict || !strings.Contains(string(again.body), protocol.CallInProgress) {
		t.Fatalf("「＊」 = %d %s, want 409 %s", again.status, again.body, protocol.CallInProgress)
	}
	now := postJSON(t, backend, protocol.StartCallPath, "Bearer "+idToken, `{"message": "金曜の通院", "script": "ハナさん、美咲さんからです。"}`)
	if now.status != http.StatusConflict || !strings.Contains(string(now.body), protocol.CallInProgress) {
		t.Fatalf("今すぐ通話 = %d %s, want 409 %s", now.status, now.body, protocol.CallInProgress)
	}
}

func assertCallInProgressGone(t *testing.T, backend, id, key, idToken, personID string) {
	t.Helper()
	again := callPhone(t, backend, http.MethodPost, protocol.PhoneCallPath, id, key, "")
	if again.status != http.StatusCreated {
		t.Fatalf("期限のあとの「＊」 = %d, want 201: %s", again.status, again.body)
	}
	var started protocol.StartedCall
	if err := json.Unmarshal(again.body, &started); err != nil || started.ID == "" {
		t.Fatalf("期限のあとの本文 = %s, want 電話の ID", again.body)
	}
	// 今すぐ通話を確かめるため、この新しい電話は終わったことにする。呼び出し中のままだと、それ自身が塞ぐ。
	if _, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Doc(started.ID).Update(t.Context(), []firestore.Update{
		{Path: "state", Value: protocol.StateEnded},
	}); err != nil {
		t.Fatal(err)
	}
	startNow(t, backend, protocol.StartCallPath, idToken)
}

func onlyCallID(t *testing.T, personID string) string {
	t.Helper()
	docs, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(docs) != 1 {
		t.Fatalf("電話の数 = %d, want 1", len(docs))
	}
	return docs[0].Ref.ID
}

func waitUntilCallState(t *testing.T, personID, callID, want string) {
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

func postLost(t *testing.T, backend, id, key string) {
	t.Helper()
	req, err := http.NewRequest(http.MethodPost, backend+protocol.PhoneCallPath, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set(protocol.PhoneIDHeader, id)
	req.Header.Set(protocol.PhoneKeyHeader, key)
	client := &http.Client{Transport: loseBody{base: http.DefaultTransport}}
	if _, err := client.Do(req); err == nil {
		t.Fatal("応答が届いた")
	}
}

// loseBody は、サーバーが応答を書き終えたあとに、その本文を捨てて届かなかったことにする。
type loseBody struct{ base http.RoundTripper }

func (l loseBody) RoundTrip(req *http.Request) (*http.Response, error) {
	resp, err := l.base.RoundTrip(req)
	if err != nil {
		return nil, err
	}
	_, _ = io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	return nil, errors.New("応答が失われた")
}

func linkHanakoPhone(t *testing.T, backend, key string) (personID, phoneID string) {
	t.Helper()
	personID, _ = registerHanako(t, backend)
	phoneID = testPhoneID(t)
	if resp := registerPhone(t, backend, protocol.DevPhoneSecret, phoneID, key); resp.status != http.StatusCreated {
		t.Fatalf("登録 = %d, want 201: %s", resp.status, resp.body)
	}
	if _, err := emulators.Firestore.Collection("phones").Doc(phoneID).Update(t.Context(), []firestore.Update{
		{Path: "watchedPersonId", Value: personID},
	}); err != nil {
		t.Fatal(err)
	}
	return personID, phoneID
}

func callDoc(t *testing.T, personID, callID string) map[string]any {
	t.Helper()
	doc, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Doc(callID).Get(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	return doc.Data()
}

func personCallDocs(t *testing.T, personID string) []map[string]any {
	t.Helper()
	docs, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	out := make([]map[string]any, len(docs))
	for i, doc := range docs {
		out[i] = doc.Data()
	}
	return out
}

func newWatchedCallServer(t *testing.T, tokens server.Tokens) *httptest.Server {
	t.Helper()
	srv, _ := newWatchedCallServerOn(t, tokens, clock.Real{})
	return srv
}

func newWatchedCallServerOn(t *testing.T, tokens server.Tokens, clk clock.Clock) (*httptest.Server, *server.Handler) {
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
	}, emulators, tokens, nil, clk)
	srv := httptest.NewServer(handler)
	t.Cleanup(func() {
		handler.Stop()
		srv.Close()
	})
	return srv, handler
}

type recordTokens struct {
	mu      sync.Mutex
	configs []*genai.CreateAuthTokenConfig
}

func (r *recordTokens) Create(_ context.Context, config *genai.CreateAuthTokenConfig) (*genai.AuthToken, error) {
	r.mu.Lock()
	r.configs = append(r.configs, config)
	r.mu.Unlock()
	return &genai.AuthToken{Name: "auth_tokens/1"}, nil
}

func (r *recordTokens) last() *genai.CreateAuthTokenConfig {
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.configs) == 0 {
		return nil
	}
	return r.configs[len(r.configs)-1]
}

func instructionText(t *testing.T, token *genai.CreateAuthTokenConfig) string {
	t.Helper()
	if token == nil || token.LiveConnectConstraints == nil || token.LiveConnectConstraints.Config == nil ||
		token.LiveConnectConstraints.Config.SystemInstruction == nil {
		t.Fatal("トークンにシステム指示を固定していない")
	}
	var b strings.Builder
	for _, part := range token.LiveConnectConstraints.Config.SystemInstruction.Parts {
		b.WriteString(part.Text)
	}
	return b.String()
}
