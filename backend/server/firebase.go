package server

import (
	"context"
	"fmt"
	"os"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
)

// ProjectID は Firebase のプロジェクトである。本物のプロジェクトはまだなく、開発者の Mac のエミュレーターだけを使う。
// demo- で始まるプロジェクトは、エミュレーターの外には届かない。
const ProjectID = "demo-kazokuai"

// Firebase は、バックエンドが使う Firebase のクライアントである。
// サーバーの SDK は、Firestore のセキュリティルールに縛られない。
type Firebase struct {
	Firestore *firestore.Client
	// Auth は、アプリから届いた家族の ID トークンを確かめる。
	Auth *auth.Client
}

// ConnectFirebase は、環境変数 FIRESTORE_EMULATOR_HOST と FIREBASE_AUTH_EMULATOR_HOST にあるエミュレーターにつなぐ。
// エミュレーターでは認証情報が要らない。
func ConnectFirebase(ctx context.Context) (Firebase, error) {
	for _, name := range []string{"FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"} {
		if os.Getenv(name) == "" {
			return Firebase{}, fmt.Errorf("環境変数 %s に Firebase のエミュレーターのアドレスを入れてください", name)
		}
	}
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: ProjectID})
	if err != nil {
		return Firebase{}, err
	}
	store, err := app.Firestore(ctx)
	if err != nil {
		return Firebase{}, err
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		store.Close()
		return Firebase{}, err
	}
	return Firebase{Firestore: store, Auth: authClient}, nil
}
