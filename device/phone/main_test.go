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

// TestMain は、家族がアプリで山田花子さんを登録したのと同じように、バックエンドの API で見守る方を登録する。
// 電話のテストは、その ID でバックエンドを動かす。
func TestMain(m *testing.M) {
	ctx := context.Background()
	var err error
	emulators, err = server.ConnectFirebase(ctx)
	if err != nil {
		log.Fatalf("%v\n%s", err, firebasetest.Hint)
	}
	backend := httptest.NewServer(server.New(server.Config{}, emulators, nil, nil))
	hanako.WatchedPerson, err = firebasetest.RegisterWatchedPerson(ctx, backend.URL, "山田花子", "ハナさん")
	backend.Close()
	if err != nil {
		log.Fatal(err)
	}
	code := m.Run()
	emulators.Firestore.Close()
	os.Exit(code)
}
