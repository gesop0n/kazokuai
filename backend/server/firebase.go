package server

import (
	"context"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
)

// Firebase は、バックエンドが使う Firebase のクライアントである。
// サーバーの SDK は、Firestore のセキュリティルールに縛られない。
type Firebase struct {
	Firestore *firestore.Client
	// Auth は、アプリから届いた家族の ID トークンを確かめる。
	Auth *auth.Client
}

// ConnectFirebase は、ResolveProject が決めたプロジェクトにつなぐ。
// demo- のプロジェクトはエミュレーターへ、それ以外は渡したプロジェクトの ID とサービスアカウントの資格情報でつなぐ。
// プロジェクトの ID は必ず明示するので、資格情報に入っている別のプロジェクトには頼らない。
func ConnectFirebase(ctx context.Context) (Firebase, error) {
	projectID, err := ResolveProject()
	if err != nil {
		return Firebase{}, err
	}
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID})
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
