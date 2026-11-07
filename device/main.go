// device は電話機のプログラムである。起動するとすぐに呼び出しを始め、1 回の電話をして終わる。
//
// 今は Mac で動かす。受話器の音声は既定のマイクとスピーカー、フックは Enter キー、
// 呼び出し音とランプはターミナルの文字である。イヤホンを付けて使う。
//
//	mise run device
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/device/mac"
	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// backend は、トークンをもらうバックエンドの URL である。backend/main.go の addr と合わせる。
const backend = "http://localhost:8080"

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	handset, err := mac.OpenHandset()
	if err != nil {
		return err
	}
	defer handset.Close()

	device := &phone.Device{
		Backend: backend,
		Gemini:  liveAPI{},
		Phone: phone.Phone{
			Handset: handset,
			Hook:    mac.NewHook(os.Stdin, os.Stdout),
			Ringer:  mac.Ringer{Out: os.Stdout},
			Lamp:    mac.Lamp{Out: os.Stdout},
		},
		Out: os.Stdout,
	}
	if err := device.Call(ctx); err != nil {
		return fmt.Errorf("電話が終わりました: %w", err)
	}
	fmt.Println("電話が終わりました。")
	return nil
}

// liveAPI は、短命トークンで Gemini の Live API につなぐ。
type liveAPI struct{}

func (liveAPI) Connect(ctx context.Context, token, model string) (phone.Session, error) {
	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		APIKey:      token,
		Backend:     genai.BackendGeminiAPI,
		HTTPOptions: genai.HTTPOptions{APIVersion: protocol.GeminiAPIVersion},
	})
	if err != nil {
		return nil, err
	}
	// モデルのほかの設定はすべてトークンに固定してあるので、ここでは渡さない
	session, err := client.Live.Connect(ctx, model, nil)
	if err != nil {
		return nil, err
	}
	return session, nil
}
