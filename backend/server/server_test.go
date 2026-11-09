package server_test

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"cloud.google.com/go/firestore"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/firebasetest"
)

// テストは、バックエンドの HTTP のサーバーを Firebase のエミュレーターにつないで動かす。
// 確かめるのは、アプリに返したものと、Firestore に残ったものである。

var emulators server.Firebase

func TestMain(m *testing.M) {
	var err error
	emulators, err = server.ConnectFirebase(context.Background())
	if err != nil {
		log.Fatalf("%v\n%s", err, firebasetest.Hint)
	}
	code := m.Run()
	emulators.Firestore.Close()
	os.Exit(code)
}

func TestRegisterWatchedPerson(t *testing.T) {
	t.Run("家族の ID トークンを付けて名前と呼び方を送ると、その家族を家族の一覧に入れた見守る方を作り、その ID を返す", func(t *testing.T) {
		backend := newBackend(t)
		misaki := signUp(t)

		resp := register(t, backend, "Bearer "+misaki.IDToken, `{"name": "山田花子", "callName": "ハナさん"}`)

		if resp.status != http.StatusCreated {
			t.Fatalf("ステータス = %d, want 201: %s", resp.status, resp.body)
		}
		var created struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(resp.body, &created); err != nil || created.ID == "" {
			t.Fatalf("返した本文 = %s, want 見守る方の ID", resp.body)
		}
		got := watchedPersonsOf(t, misaki.UID)
		if len(got) != 1 || got[0].Ref.ID != created.ID {
			t.Fatalf("美咲さんの見守る方 = %v, want 返した ID の 1 人", ids(got))
		}
		data := got[0].Data()
		if data["name"] != "山田花子" || data["callName"] != "ハナさん" {
			t.Errorf("見守る方 = %v, want 名前は山田花子、呼び方はハナさん", data)
		}
		if family, _ := data["familyUids"].([]any); len(family) != 1 || family[0] != misaki.UID {
			t.Errorf("家族の一覧 = %v, want 美咲さんの uid だけ", data["familyUids"])
		}
	})

	t.Run("名前と呼び方の前後の空白は除いて登録する", func(t *testing.T) {
		backend := newBackend(t)
		misaki := signUp(t)

		resp := register(t, backend, "Bearer "+misaki.IDToken, `{"name": " 山田花子　", "callName": "\tハナさん "}`)

		if resp.status != http.StatusCreated {
			t.Fatalf("ステータス = %d, want 201: %s", resp.status, resp.body)
		}
		data := watchedPersonsOf(t, misaki.UID)[0].Data()
		if data["name"] != "山田花子" || data["callName"] != "ハナさん" {
			t.Errorf("見守る方 = %v, want 空白のない 山田花子 と ハナさん", data)
		}
	})

	t.Run("ID トークンがない頼みと、エミュレーターが出していない ID トークンの頼みは断る", func(t *testing.T) {
		backend := newBackend(t)
		for name, authorization := range map[string]string{
			"ヘッダーがない":    "",
			"Bearer でない": "Basic bWlzYWtpOmhhbmFzYW4=",
			"偽の ID トークン": "Bearer not-an-id-token",
		} {
			t.Run(name, func(t *testing.T) {
				resp := register(t, backend, authorization, `{"name": "山田花子", "callName": "ハナさん"}`)

				if resp.status != http.StatusUnauthorized {
					t.Errorf("ステータス = %d, want 401: %s", resp.status, resp.body)
				}
			})
		}
	})

	t.Run("すでに見守る方がいる家族の登録は断り、2 人目を作らない", func(t *testing.T) {
		backend := newBackend(t)
		misaki := signUp(t)
		first := register(t, backend, "Bearer "+misaki.IDToken, `{"name": "山田花子", "callName": "ハナさん"}`)
		if first.status != http.StatusCreated {
			t.Fatalf("1 人目のステータス = %d, want 201: %s", first.status, first.body)
		}

		second := register(t, backend, "Bearer "+misaki.IDToken, `{"name": "山田太郎", "callName": "タロウさん"}`)

		if second.status != http.StatusConflict {
			t.Errorf("2 人目のステータス = %d, want 409: %s", second.status, second.body)
		}
		got := watchedPersonsOf(t, misaki.UID)
		if len(got) != 1 || got[0].Data()["name"] != "山田花子" {
			t.Errorf("美咲さんの見守る方 = %v, want 山田花子さんだけ", names(got))
		}
	})

	t.Run("名前か呼び方が空なら断り、見守る方を作らない", func(t *testing.T) {
		backend := newBackend(t)
		for name, body := range map[string]string{
			"名前が空":     `{"name": "", "callName": "ハナさん"}`,
			"呼び方が空白だけ": `{"name": "山田花子", "callName": "　 "}`,
			"JSON でない": `山田花子`,
		} {
			t.Run(name, func(t *testing.T) {
				misaki := signUp(t)

				resp := register(t, backend, "Bearer "+misaki.IDToken, body)

				if resp.status != http.StatusBadRequest {
					t.Errorf("ステータス = %d, want 400: %s", resp.status, resp.body)
				}
				if got := watchedPersonsOf(t, misaki.UID); len(got) != 0 {
					t.Errorf("美咲さんの見守る方 = %v, want いない", names(got))
				}
			})
		}
	})
}

func newBackend(t *testing.T) string {
	t.Helper()
	backend := httptest.NewServer(server.New(server.Config{}, emulators, nil, nil, nil))
	t.Cleanup(backend.Close)
	return backend.URL
}

func signUp(t *testing.T) firebasetest.Family {
	t.Helper()
	family, err := firebasetest.SignUp(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	return family
}

type response struct {
	status int
	body   []byte
	header http.Header
}

// register は、アプリの L6 と同じように見守る方の登録を頼む。authorization が空なら、ヘッダーを付けない。
func register(t *testing.T, backend, authorization, body string) response {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, backend+"/watched-persons", bytes.NewBufferString(body))
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

// watchedPersonsOf は、家族の一覧に uid がある見守る方を、アプリと同じ条件で Firestore から読む。
func watchedPersonsOf(t *testing.T, uid string) []*firestore.DocumentSnapshot {
	t.Helper()
	docs, err := emulators.Firestore.Collection("watchedPersons").
		Where("familyUids", "array-contains", uid).
		Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	return docs
}

func ids(docs []*firestore.DocumentSnapshot) []string {
	var ids []string
	for _, doc := range docs {
		ids = append(ids, doc.Ref.ID)
	}
	return ids
}

func names(docs []*firestore.DocumentSnapshot) []any {
	var names []any
	for _, doc := range docs {
		names = append(names, doc.Data()["name"])
	}
	return names
}
