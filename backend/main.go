// backend は、デバイスに短命トークンを渡すバックエンドのプログラムである。
// 見守る方はフラグで渡す。Gemini の API キーは環境変数 GEMINI_API_KEY から読み、デバイスには渡さない。
//
//	mise run backend -- --name 山田花子 --call-name ハナさん
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
	// addr は、デバイスがトークンをもらいに来るアドレスである。device/main.go の backend と合わせる。
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
	fs.StringVar(&config.Name, "name", "", "見守る方の名前(必須)")
	fs.StringVar(&config.CallName, "call-name", "", "AI が見守る方を呼ぶときの呼び方(必須)。例: ハナさん")
	fs.StringVar(&config.Model, "model", defaultModel, "Live API のモデル")
	fs.StringVar(&config.Voice, "voice", defaultVoice, "AI の声の名前")
	fs.DurationVar(&config.RingTimeout, "ring-timeout", defaultRingTimeout, "呼び出しの上限")
	fs.DurationVar(&config.MaxCall, "max-call", defaultMaxCall, "電話の長さの上限")
	fs.DurationVar(&config.WrapUpBefore, "wrap-up-before", defaultWrapUpBefore, "締めの合図を送る時間")
	fs.DurationVar(&config.TokenMargin, "token-margin", defaultTokenMargin, "トークンの有効期限の余裕")
}

func run(config server.Config) error {
	if config.Name == "" || config.CallName == "" {
		return errors.New("--name と --call-name で見守る方の名前と呼び方を指定してください")
	}
	if config.RingTimeout+config.MaxCall > connectionLimit {
		limit := protocol.DurationWords(connectionLimit)
		return fmt.Errorf("呼び出しの上限（--ring-timeout=%s）と電話の長さの上限（--max-call=%s）の合計が %s を超えています。Live API の接続は呼び出しが始まってから約 %s で切れるので、起動できません",
			protocol.DurationWords(config.RingTimeout),
			protocol.DurationWords(config.MaxCall),
			limit, limit)
	}
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		return errors.New("環境変数 GEMINI_API_KEY に Gemini の API キーを入れてください")
	}
	client, err := genai.NewClient(context.Background(), &genai.ClientConfig{
		APIKey:      apiKey,
		Backend:     genai.BackendGeminiAPI,
		HTTPOptions: genai.HTTPOptions{APIVersion: protocol.GeminiAPIVersion},
	})
	if err != nil {
		return err
	}
	log.Printf("http://%s でトークンを渡します。モデル: %s、声: %s", addr, config.Model, config.Voice)
	return http.ListenAndServe(addr, server.New(config, client.AuthTokens, systemClock{}))
}

type systemClock struct{}

func (systemClock) Now() time.Time { return time.Now() }
