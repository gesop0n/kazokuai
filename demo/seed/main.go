// demo/seed は、審査員用アカウントと見本の電話を作る。もう一度実行すると、そのアカウントの電話を見本に戻す。
// プロジェクトは --project で渡す。環境変数のプロジェクトや gcloud の既定は使わない。
// メールアドレスは JUDGE_EMAIL、パスワードは JUDGE_PASSWORD。パスワードはリポジトリに置かない。
// demo- のプロジェクトは Firebase のエミュレーターが要る。それ以外は、エミュレーターの変数があると実行しない。
//
//	mise run demo:seed -- --project=PROJECT_ID
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
)

func main() {
	if err := run(context.Background(), os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		if errors.Is(err, errUsage) {
			os.Exit(2)
		}
		os.Exit(1)
	}
}

var errUsage = errors.New("使い方: demo-seed --project=ID")

func run(ctx context.Context, args []string) error {
	req, err := requestFrom(args)
	if err != nil {
		return err
	}
	if err := validateRequest(req); err != nil {
		return err
	}
	// クライアントを開く前に、渡したプロジェクトへ揃える。
	// 既定のプロジェクトが別にあっても、SDK はここを見る。
	for _, key := range []string{"GOOGLE_CLOUD_PROJECT", "GOOGLE_PROJECT", "CLOUDSDK_CORE_PROJECT"} {
		if err := os.Setenv(key, req.ProjectID); err != nil {
			return err
		}
	}
	store, accounts, err := openFirebase(ctx, req.ProjectID)
	if err != nil {
		return err
	}
	defer store.Close()
	result, err := Seed(ctx, store, accounts, req)
	if err != nil {
		return err
	}
	fmt.Printf("審査員のメールアドレス: %s\n", result.Email)
	fmt.Printf("審査員の名前: %s\n", judgeDisplayName)
	fmt.Printf("見守る方の ID: %s\n", result.WatchedPersonID)
	fmt.Printf("電話を %d 件に戻しました。出なかった電話は %d 件です。\n", result.Calls, result.Missed)
	fmt.Println("もう一度実行すると、このアカウントの電話を見本に戻します。")
	return nil
}

func requestFrom(args []string) (Request, error) {
	project, err := parseProject(args)
	if err != nil {
		return Request{}, err
	}
	return Request{
		ProjectID:     project,
		Email:         strings.TrimSpace(os.Getenv("JUDGE_EMAIL")),
		Password:      os.Getenv("JUDGE_PASSWORD"),
		FirestoreHost: os.Getenv("FIRESTORE_EMULATOR_HOST"),
		AuthHost:      os.Getenv("FIREBASE_AUTH_EMULATOR_HOST"),
	}, nil
}

func parseProject(args []string) (string, error) {
	fs := flag.NewFlagSet("demo-seed", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	project := fs.String("project", "", "プロジェクトの ID")
	if err := fs.Parse(args); err != nil {
		return "", fmt.Errorf("%w\n%s", errUsage, err)
	}
	if strings.TrimSpace(*project) == "" {
		return "", fmt.Errorf("%w\nプロジェクトの ID が要ります。--project で渡してください", errUsage)
	}
	return strings.TrimSpace(*project), nil
}

func openFirebase(ctx context.Context, projectID string) (*firestore.Client, *auth.Client, error) {
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: projectID})
	if err != nil {
		return nil, nil, err
	}
	store, err := app.Firestore(ctx)
	if err != nil {
		return nil, nil, err
	}
	accounts, err := app.Auth(ctx)
	if err != nil {
		store.Close()
		return nil, nil, err
	}
	return store, accounts, nil
}
