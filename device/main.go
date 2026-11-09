// device は電話機のプログラムである。起動するとバックエンドにつながり続け、今すぐ通話の指示で電話をする。
//
// macOS では、受話器の音声は既定のマイクとスピーカー、フックは Enter キー、
// 呼び出し音とランプはターミナルの文字である。イヤホンを付けて使う。
// Linux では、電話機の受話器とフックと呼び出し音を使い、ランプはログだけを書く。
// 部品の確認は、電話機の上で `device check devices|speaker|mic|hook|ringer|keypad` である。
//
// 見守る方の ID は、起動するときに渡す。受話器を開く前に確かめる。
// バックエンドの URL は --backend で渡す。既定は http://localhost:8080 で、https は wss でつなぐ。
// 合言葉は環境変数 PHONE_SECRET から読む。未設定なら開発用の合言葉を使う。どのリクエストにも付ける。
// 電話機の音声とフックは環境変数から読む。空なら受話器の配線の既定である。
// device check は /etc/kazokuai/device.env があれば読み、空の環境変数も含めて上書きする。
//
//	mise run device -- --watched-person <見守る方の ID>
//	mise run device -- --watched-person <見守る方の ID> --backend https://kazokuai-….run.app
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

	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) > 0 && args[0] == "check" {
		part, err := parseCheck(args[1:])
		if err != nil {
			return err
		}
		return runCheck(part)
	}
	person, backendURL, err := parseArgs(args)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	opened, cleanup, err := openPhone(os.Stdout)
	if err != nil {
		return err
	}
	defer cleanup()

	device := &phone.Device{
		Backend:       backendURL,
		Secret:        phoneSecret(os.Getenv("PHONE_SECRET")),
		WatchedPerson: person,
		Gemini:        liveAPI{},
		Phone:         opened,
		Out:           os.Stdout,
		Clock:         realClock{},
	}
	if err := device.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
		return fmt.Errorf("電話機が終わりました: %w", err)
	}
	return nil
}

// parseArgs は、--watched-person と --backend を読む。見守る方の ID が無ければ、受話器を開かずにエラーを返す。
func parseArgs(args []string) (person, backend string, err error) {
	fs := flag.NewFlagSet("device", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	id := fs.String("watched-person", "", "見守る方の ID")
	backendURL := fs.String("backend", "http://localhost:8080", "バックエンドの URL。https は wss でつなぐ")
	if err := fs.Parse(args); err != nil {
		return "", "", err
	}
	if strings.TrimSpace(*id) == "" {
		return "", "", errors.New("見守る方の ID が要ります。--watched-person で渡してください")
	}
	if strings.TrimSpace(*backendURL) == "" {
		return "", "", errors.New("バックエンドの URL が要ります。--backend で渡してください")
	}
	return *id, *backendURL, nil
}

// parseCheck は、`device check` の部品名を読む。機器を開く前に、名前が違えば戻る。
func parseCheck(args []string) (string, error) {
	const usage = "確認する部品を1つ指定してください: devices, speaker, mic, hook, ringer, keypad"
	if len(args) != 1 {
		return "", errors.New(usage)
	}
	switch args[0] {
	case "devices", "speaker", "mic", "hook", "ringer", "keypad":
		return args[0], nil
	default:
		return "", fmt.Errorf("確認できない部品です: %s。%s", args[0], usage)
	}
}

// phoneSecret は、環境変数の合言葉を返す。未設定なら開発用の合言葉である。
func phoneSecret(env string) string {
	if env != "" {
		return env
	}
	return protocol.DevPhoneSecret
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
