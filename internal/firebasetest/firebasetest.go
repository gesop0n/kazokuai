// Package firebasetest は、Go のテストから Firebase のエミュレーターを使う道具である。
// テストは scripts/emulators_exec.sh の中で動かす。エミュレーターの場所は環境変数から読む。
package firebasetest

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
)

// Hint は、エミュレーターの外でテストを動かしたときに出す案内である。
const Hint = "Go のテストは、Firebase のエミュレーターの中で動かす。mise run check か、scripts/emulators_exec.sh 'go test ./...' で動かす"

// Family は、Auth のエミュレーターに作った家族のアカウントである。
type Family struct {
	UID string
	// IDToken は、アプリがバックエンドに送るのと同じ Firebase の ID トークンである。
	IDToken string
}

// SignUp は、Auth のエミュレーターに、アプリの新規登録と同じ API で家族のアカウントを作る。
// メールアドレスは毎回新しく作るので、テストどうしで家族が重ならない。
func SignUp(ctx context.Context) (Family, error) {
	host := os.Getenv("FIREBASE_AUTH_EMULATOR_HOST")
	if host == "" {
		return Family{}, fmt.Errorf("環境変数 FIREBASE_AUTH_EMULATOR_HOST がない。%s", Hint)
	}
	email := "family-" + strings.ToLower(rand.Text()) + "@example.com"
	var account struct {
		LocalID string `json:"localId"`
		IDToken string `json:"idToken"`
	}
	// エミュレーターは API キーを確かめないので、どんな値でもよい
	url := "http://" + host + "/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator"
	err := postJSON(ctx, url, "", map[string]any{
		"email":             email,
		"password":          "hanasan1234",
		"returnSecureToken": true,
	}, http.StatusOK, &account)
	if err != nil {
		return Family{}, fmt.Errorf("家族のアカウントを作れなかった: %w", err)
	}
	return Family{UID: account.LocalID, IDToken: account.IDToken}, nil
}

// RegisterWatchedPerson は、新しい家族として、backend のバックエンドに見守る方を登録し、その ID を返す。
// アプリの L6 と同じ API を使う。
func RegisterWatchedPerson(ctx context.Context, backend, name, callName string) (string, error) {
	family, err := SignUp(ctx)
	if err != nil {
		return "", err
	}
	var registered struct {
		ID string `json:"id"`
	}
	err = postJSON(ctx, backend+"/watched-persons", family.IDToken, map[string]string{
		"name":     name,
		"callName": callName,
	}, http.StatusCreated, &registered)
	if err != nil {
		return "", fmt.Errorf("見守る方を登録できなかった: %w", err)
	}
	return registered.ID, nil
}

func postJSON(ctx context.Context, url, idToken string, body any, wantStatus int, out any) error {
	data, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if idToken != "" {
		req.Header.Set("Authorization", "Bearer "+idToken)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != wantStatus {
		text, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("%s が %s を返した: %s", url, resp.Status, text)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}
