// backend は、デバイスに短命トークンを渡すバックエンドのプログラムである。
// 見守る方はフラグで渡す。Gemini の API キーは環境変数 GEMINI_API_KEY から読み、デバイスには渡さない。
//
//	mise run backend -- --name 山田花子 --call-name ハナさん
package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"net/http"
	"os"
	"time"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// 既定値はここにまとめる。
const (
	// addr は、デバイスがトークンをもらいに来るアドレスである。device/main.go の backend と合わせる。
	addr         = "localhost:8080"
	defaultModel = "gemini-3.8-live"
	defaultVoice = "Kore"
)

func main() {
	var config server.Config
	flag.StringVar(&config.Name, "name", "", "見守る方の名前(必須)")
	flag.StringVar(&config.CallName, "call-name", "", "AI が見守る方を呼ぶときの呼び方(必須)。例: ハナさん")
	flag.StringVar(&config.Model, "model", defaultModel, "Live API のモデル")
	flag.StringVar(&config.Voice, "voice", defaultVoice, "AI の声の名前")
	flag.Parse()

	if err := run(config); err != nil {
		log.Fatal(err)
	}
}

func run(config server.Config) error {
	if config.Name == "" || config.CallName == "" {
		return errors.New("--name と --call-name で見守る方の名前と呼び方を指定してください")
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
