package phone_test

import (
	"context"
	"log"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/firebasetest"
)

// emulators は、テストの中で動かすバックエンドがつなぐ Firebase のエミュレーターである。
var emulators server.Firebase

// familyToken は、山田花子さんを登録した家族の ID トークンである。今すぐ通話のテストが使う。
var familyToken string

// hanakoID は、TestMain が登録した山田花子さんの ID である。
var hanakoID string

// TestMain は、家族がアプリで山田花子さんを登録したのと同じように、バックエンドの API で見守る方を登録する。
// 電話のテストは、その家族の ID トークンで今すぐ通話を始める。
func TestMain(m *testing.M) {
	ctx := context.Background()
	var err error
	emulators, err = server.ConnectFirebase(ctx)
	if err != nil {
		log.Fatalf("%v\n%s", err, firebasetest.Hint)
	}
	backend := httptest.NewServer(server.New(server.Config{}, emulators, nil, nil, nil))
	family, err := firebasetest.SignUp(ctx)
	if err != nil {
		backend.Close()
		log.Fatal(err)
	}
	familyToken = family.IDToken
	hanakoID, err = firebasetest.RegisterWatchedPersonAs(ctx, backend.URL, family, "山田花子", "ハナさん")
	backend.Close()
	if err != nil {
		log.Fatal(err)
	}
	code := m.Run()
	emulators.Firestore.Close()
	os.Exit(code)
}
