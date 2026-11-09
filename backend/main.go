// backend は、デバイスに短命トークンを渡し、アプリから見守る方の登録と今すぐ通話を受け、電話の報告からまとめを作るバックエンドのプログラムである。
// 電話をかける見守る方は、電話機が接続するときに渡す。名前と呼び方は、トークンを作るたびに Firestore から読む。
// Gemini の API キーは環境変数 GEMINI_API_KEY から読み、デバイスには渡さない。
// Firebase は、環境変数 FIRESTORE_EMULATOR_HOST と FIREBASE_AUTH_EMULATOR_HOST のエミュレーターを使う。
//
//	mise run backend
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// 既定値と、Live API の接続の上限はここにまとめる。
// 接続は呼び出しが始まってから約 connectionLimit で切れる。
const (
	// addr は、デバイスがトークンをもらいに来て、アプリが見守る方を登録しに来るアドレスである。
	// device/main.go の backend と、mobile/lib/data/backend.dart の既定値と合わせる。
	addr                = "localhost:8080"
	defaultModel        = "gemini-3.8-live"
	defaultVoice        = "Kore"
	defaultRingTimeout  = time.Minute
	defaultMaxCall      = 5 * time.Minute
	defaultWrapUpBefore = time.Minute
	defaultTokenMargin  = 5 * time.Minute
	connectionLimit     = 10 * time.Minute
)

func main() {
	var config server.Config
	defineFlags(flag.CommandLine, &config)
	flag.Parse()

	if err := run(config); err != nil {
		log.Fatal(err)
	}
}

func defineFlags(fs *flag.FlagSet, config *server.Config) {
	fs.StringVar(&config.Model, "model", defaultModel, "Live API のモデル")
	fs.StringVar(&config.Voice, "voice", defaultVoice, "AI の声の名前")
	fs.DurationVar(&config.RingTimeout, "ring-timeout", defaultRingTimeout, "呼び出しの上限")
	fs.DurationVar(&config.MaxCall, "max-call", defaultMaxCall, "電話の長さの上限")
	fs.DurationVar(&config.WrapUpBefore, "wrap-up-before", defaultWrapUpBefore, "締めの合図を送る時間")
	fs.DurationVar(&config.TokenMargin, "token-margin", defaultTokenMargin, "トークンの有効期限の余裕")
	fs.StringVar(&config.SummaryModel, "summary-model", server.DefaultSummaryModel, "まとめに使う Gemini のモデル")
}

func run(config server.Config) error {
	if config.SummaryRetryWait == 0 {
		config.SummaryRetryWait = time.Second
	}
	if config.RingTimeout+config.MaxCall > connectionLimit {
		limit := protocol.DurationWords(connectionLimit)
		return fmt.Errorf("呼び出しの上限（--ring-timeout=%s）と電話の長さの上限（--max-call=%s）の合計が %s を超えています。Live API の接続は呼び出しが始まってから約 %s で切れるので、起動できません",
			protocol.DurationWords(config.RingTimeout),
			protocol.DurationWords(config.MaxCall),
			limit, limit)
	}
	if config.WrapUpBefore > config.MaxCall {
		return fmt.Errorf("締めの合図を送る時間（--wrap-up-before=%s）が電話の長さの上限（--max-call=%s）より長いので、起動できません。合図に書く残り時間が、実際に残っている時間と違ってしまいます",
			protocol.DurationWords(config.WrapUpBefore),
			protocol.DurationWords(config.MaxCall))
	}
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		return errors.New("環境変数 GEMINI_API_KEY に Gemini の API キーを入れてください")
	}
	ctx := context.Background()
	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		APIKey:      apiKey,
		Backend:     genai.BackendGeminiAPI,
		HTTPOptions: genai.HTTPOptions{APIVersion: protocol.GeminiAPIVersion},
	})
	if err != nil {
		return err
	}
	firebase, err := server.ConnectFirebase(ctx)
	if err != nil {
		return err
	}
	defer firebase.Firestore.Close()
	log.Printf("http://%s で電話機の接続とトークンを受け、見守る方の登録と今すぐ通話と電話の報告を受けます。モデル: %s、声: %s、まとめ: %s", addr, config.Model, config.Voice, config.SummaryModel)
	return http.ListenAndServe(addr, server.New(config, firebase, client.AuthTokens, client.Models, systemClock{}))
}

type systemClock struct{}

func (systemClock) Now() time.Time { return time.Now() }
