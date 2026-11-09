package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"

	"google.golang.org/genai"
)

// draftScriptBody は、通話内容の案を頼む本文である。
type draftScriptBody struct {
	// Message は、家族が入れた伝えたいことである。
	Message string `json:"message"`
}

// scriptDraft は、Gemini に作らせる通話内容である。JSON Schema はこの構造体から作る。
type scriptDraft struct {
	Script string `json:"script"`
}

// draftedScript は、作った通話内容の案を返すレスポンスである。
type draftedScript struct {
	Script string `json:"script"`
}

// scriptSchema は、scriptDraft から作った JSON Schema である。
var scriptSchema = schemaOf(scriptDraft{})

// scriptInstruction は、通話内容の案を作る Gemini への指示である。Live API は使わない。
const scriptInstruction = `あなたは、家族の伝えたいことから、電話で AI が見守る方に話す通話内容を作ります。

# 通話内容
- 見守る方へ話しかける言葉だけを書いてください。
- 依頼に書いてある呼び方で呼びかけ、家族からの伝言として、伝えたいことをやさしい敬語で伝えてください。
- 説明や見出しは書かないでください。
`

// draftScript は、ID トークンを確かめた家族の伝えたいことと、その見守る方の呼び方から、通話内容の案を作る。
// 電話の文書は作らない。電話機にも指示を送らない。
func (s *server) draftScript(w http.ResponseWriter, r *http.Request) {
	idToken, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || idToken == "" {
		http.Error(w, "Authorization ヘッダーに、家族の ID トークンを Bearer で入れてください", http.StatusUnauthorized)
		return
	}
	token, err := s.firebase.Auth.VerifyIDToken(r.Context(), idToken)
	if err != nil {
		log.Printf("家族の ID トークンを確かめられなかった: %v", err)
		http.Error(w, "家族の ID トークンを確かめられなかった", http.StatusUnauthorized)
		return
	}
	var req draftScriptBody
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxStartCall)).Decode(&req); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return
	}
	message := strings.TrimSpace(req.Message)
	if message == "" {
		http.Error(w, "伝えたいことを入れてください", http.StatusBadRequest)
		return
	}
	personID, err := findFamilyPerson(r.Context(), s.firebase.Firestore, token.UID)
	if errors.Is(err, errNotFamily) {
		http.Error(w, "この見守る方の家族ではないので、通話内容の案を作れません", http.StatusForbidden)
		return
	}
	if err != nil {
		log.Printf("家族の見守る方を読めなかった: %v", err)
		http.Error(w, "見守る方を読めなかった", http.StatusInternalServerError)
		return
	}
	person, err := readWatchedPerson(r.Context(), s.firebase.Firestore, personID)
	if err != nil {
		log.Printf("見守る方 %s を読めなかった: %v", personID, err)
		http.Error(w, "見守る方を読めなかった", http.StatusInternalServerError)
		return
	}
	script, err := s.draftCallScript(r.Context(), person.CallName, message)
	if err != nil {
		log.Printf("通話内容の案を作れなかった: %v", err)
		http.Error(w, "通話内容の案を作れなかった", http.StatusBadGateway)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(draftedScript{Script: script})
}

// draftCallScript は、呼び方と伝えたいことから、generateContent で通話内容の案を 1 回作る。
func (s *server) draftCallScript(ctx context.Context, callName, message string) (string, error) {
	if s.summarizer == nil {
		return "", errors.New("通話内容の案を作る Gemini がない")
	}
	response, err := s.summarizer.GenerateContent(ctx, s.summaryModel(), scriptContents(callName, message), scriptConfig())
	if err != nil {
		return "", err
	}
	text := strings.TrimSpace(response.Text())
	if text == "" {
		return "", errors.New("Gemini の応答に通話内容がなかった")
	}
	var draft scriptDraft
	if err := json.Unmarshal([]byte(text), &draft); err != nil {
		return "", fmt.Errorf("通話内容の JSON を読めなかった: %w", err)
	}
	script := strings.TrimSpace(draft.Script)
	if script == "" {
		return "", errors.New("通話内容が空")
	}
	return script, nil
}

func scriptContents(callName, message string) []*genai.Content {
	text := fmt.Sprintf("呼び方: %s\n\n伝えたいこと:\n%s\n", callName, message)
	return []*genai.Content{genai.NewContentFromText(text, genai.RoleUser)}
}

func scriptConfig() *genai.GenerateContentConfig {
	return &genai.GenerateContentConfig{
		SystemInstruction:  genai.NewContentFromText(scriptInstruction, genai.RoleUser),
		ResponseMIMEType:   "application/json",
		ResponseJsonSchema: scriptSchema,
	}
}
