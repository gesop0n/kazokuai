// device は電話機のプログラムである。起動するとバックエンドにつながり続け、今すぐ通話の指示で電話をする。
//
// 今は Mac で動かす。受話器の音声は既定のマイクとスピーカー、フックは Enter キー、
// 呼び出し音とランプはターミナルの文字である。イヤホンを付けて使う。
// 見守る方の ID は、起動するときに渡す。受話器を開く前に確かめる。
//
//	mise run device -- --watched-person <見守る方の ID>
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"strings"
	"time"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/device/mac"
	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// backend は、トークンをもらうバックエンドの URL である。backend/main.go の addr と合わせる。
const backend = "http://localhost:8080"

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string) error {
	person, err := watchedPersonID(args)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	handset, err := mac.OpenHandset()
	if err != nil {
		return err
	}
	defer handset.Close()

	device := &phone.Device{
		Backend:       backend,
		WatchedPerson: person,
		Gemini:        liveAPI{},
		Phone: phone.Phone{
			Handset: handset,
			Hook:    mac.NewHook(os.Stdin, os.Stdout),
			Ringer:  mac.Ringer{Out: os.Stdout},
			Lamp:    mac.Lamp{Out: os.Stdout},
		},
		Out:   os.Stdout,
		Clock: realClock{},
	}
	if err := device.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
		return fmt.Errorf("電話機が終わりました: %w", err)
	}
	return nil
}

// watchedPersonID は、--watched-person の値を返す。無ければ、受話器を開かずにエラーを返す。
func watchedPersonID(args []string) (string, error) {
	fs := flag.NewFlagSet("device", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	id := fs.String("watched-person", "", "見守る方の ID")
	if err := fs.Parse(args); err != nil {
		return "", err
	}
	if strings.TrimSpace(*id) == "" {
		return "", errors.New("見守る方の ID が要ります。--watched-person で渡してください")
	}
	return *id, nil
}

// realClock は、そのマシンの時計である。
type realClock struct{}

func (realClock) Now() time.Time { return time.Now() }

func (realClock) NewTimer(d time.Duration) phone.Timer {
	return realTimer{time.NewTimer(d)}
}

type realTimer struct{ timer *time.Timer }

func (t realTimer) Chan() <-chan time.Time { return t.timer.C }
func (t realTimer) Stop()                  { t.timer.Stop() }

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
