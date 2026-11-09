package server_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

func TestDraftScript(t *testing.T) {
	const message = "金曜の通院、10時に迎えに行くと伝えて"
	const callName = "タロウさん"
	const drafted = "「タロウさん、金曜の通院は朝10時にお迎えに行くそうです。」"

	t.Run("ログインした家族の伝えたいことと、見守る方の呼び方から、通話内容の案を返す", func(t *testing.T) {
		drafts := &fakeDrafts{text: `{"script":"` + drafted + `"}`}
		backend := newDraftBackend(t, drafts)
		misaki := signUp(t)
		created := register(t, backend, "Bearer "+misaki.IDToken, `{"name":"山田太郎","callName":"`+callName+`"}`)
		if created.status != http.StatusCreated {
			t.Fatalf("登録のステータス = %d, want 201: %s", created.status, created.body)
		}
		var person struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(created.body, &person); err != nil || person.ID == "" {
			t.Fatalf("登録の本文 = %s, want 見守る方の ID", created.body)
		}
		before := callCount(t, person.ID)

		resp := postJSON(t, backend, protocol.DraftScriptPath, "Bearer "+misaki.IDToken, `{"message":"  `+message+`\n"}`)

		if resp.status != http.StatusOK {
			t.Fatalf("ステータス = %d, want 200: %s", resp.status, resp.body)
		}
		var got struct {
			Script string `json:"script"`
		}
		if err := json.Unmarshal(resp.body, &got); err != nil {
			t.Fatalf("本文 = %s: %v", resp.body, err)
		}
		if got.Script != drafted {
			t.Errorf("通話内容 = %q, want %q", got.Script, drafted)
		}
		if callCount(t, person.ID) != before {
			t.Errorf("案を頼んだだけで電話が %d 件増えた", callCount(t, person.ID)-before)
		}
		if len(drafts.requests) != 1 {
			t.Fatalf("Gemini を呼んだ回数 = %d, want 1", len(drafts.requests))
		}
		req := drafts.requests[0]
		if req.model != server.DefaultSummaryModel {
			t.Errorf("モデル = %q, want %s。Live API では作らない", req.model, server.DefaultSummaryModel)
		}
		prompt := draftPrompt(req)
		for _, want := range []string{callName, message, "通話内容"} {
			if !strings.Contains(prompt, want) {
				t.Errorf("Gemini への依頼に %q がない:\n%s", want, prompt)
			}
		}
	})

	t.Run("Gemini が案を作れなければ、案を返さない", func(t *testing.T) {
		for _, name := range []string{"失敗", "空の案", "JSON でない"} {
			t.Run(name, func(t *testing.T) {
				drafts := &fakeDrafts{err: errors.New("使えない")}
				switch name {
				case "空の案":
					drafts = &fakeDrafts{text: `{"script":"  "}`}
				case "JSON でない":
					drafts = &fakeDrafts{text: "案です"}
				}
				backend := newDraftBackend(t, drafts)
				misaki := signUp(t)
				created := register(t, backend, "Bearer "+misaki.IDToken, `{"name":"山田太郎","callName":"`+callName+`"}`)
				if created.status != http.StatusCreated {
					t.Fatalf("登録のステータス = %d, want 201: %s", created.status, created.body)
				}

				resp := postJSON(t, backend, protocol.DraftScriptPath, "Bearer "+misaki.IDToken, `{"message":"`+message+`"}`)

				if resp.status != http.StatusBadGateway {
					t.Errorf("ステータス = %d, want 502: %s", resp.status, resp.body)
				}
				var got struct {
					Script string `json:"script"`
				}
				_ = json.Unmarshal(resp.body, &got)
				if got.Script != "" {
					t.Errorf("失敗なのに通話内容を返した: %s", resp.body)
				}
			})
		}
	})

	t.Run("トークンがない頼み、見守る方がいない家族、空の伝えたいことは断り、Gemini を呼ばない", func(t *testing.T) {
		drafts := &fakeDrafts{text: `{"script":"` + drafted + `"}`}
		backend := newDraftBackend(t, drafts)
		stranger := signUp(t)
		for _, tc := range []struct {
			name string
			auth string
			body string
			want int
		}{
			{name: "トークンがない", auth: "", body: `{"message":"` + message + `"}`, want: http.StatusUnauthorized},
			{name: "見守る方がいない", auth: "Bearer " + stranger.IDToken, body: `{"message":"` + message + `"}`, want: http.StatusForbidden},
			{name: "伝えたいことが空", auth: "Bearer " + stranger.IDToken, body: `{"message":"  "}`, want: http.StatusBadRequest},
		} {
			t.Run(tc.name, func(t *testing.T) {
				resp := postJSON(t, backend, protocol.DraftScriptPath, tc.auth, tc.body)

				if resp.status != tc.want {
					t.Errorf("ステータス = %d, want %d: %s", resp.status, tc.want, resp.body)
				}
			})
		}
		if len(drafts.requests) != 0 {
			t.Errorf("断ったのに Gemini を %d 回呼んだ", len(drafts.requests))
		}
	})
}

func newDraftBackend(t *testing.T, drafts server.Summarizer) string {
	t.Helper()
	backend := httptest.NewServer(server.New(server.Config{}, emulators, nil, drafts, nil))
	t.Cleanup(backend.Close)
	return backend.URL
}

func postJSON(t *testing.T, backend, path, authorization, body string) response {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, backend+path, bytes.NewBufferString(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	if authorization != "" {
		req.Header.Set("Authorization", authorization)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return response{status: resp.StatusCode, body: data}
}

func callCount(t *testing.T, personID string) int {
	t.Helper()
	docs, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	return len(docs)
}

// fakeDrafts は、通話内容の案のための generateContent に決めた応答を返す。
type fakeDrafts struct {
	requests []draftRequest
	text     string
	err      error
}

type draftRequest struct {
	model    string
	contents []*genai.Content
	config   *genai.GenerateContentConfig
}

func (f *fakeDrafts) GenerateContent(ctx context.Context, model string, contents []*genai.Content, config *genai.GenerateContentConfig) (*genai.GenerateContentResponse, error) {
	f.requests = append(f.requests, draftRequest{model: model, contents: contents, config: config})
	if f.err != nil {
		return nil, f.err
	}
	return &genai.GenerateContentResponse{
		Candidates: []*genai.Candidate{{
			Content: &genai.Content{
				Role:  genai.RoleModel,
				Parts: []*genai.Part{{Text: f.text}},
			},
		}},
	}, nil
}

func draftPrompt(req draftRequest) string {
	var b strings.Builder
	if req.config != nil {
		b.WriteString(draftContentText(req.config.SystemInstruction))
		b.WriteByte('\n')
	}
	for _, content := range req.contents {
		b.WriteString(draftContentText(content))
		b.WriteByte('\n')
	}
	return b.String()
}

func draftContentText(content *genai.Content) string {
	if content == nil {
		return ""
	}
	var b strings.Builder
	for _, part := range content.Parts {
		b.WriteString(part.Text)
	}
	return b.String()
}
