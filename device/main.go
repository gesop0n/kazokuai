// device は電話機のプログラムである。起動するとバックエンドにつながり続け、今すぐ通話の指示で電話をする。
//
// macOS では、受話器の音声は既定のマイクとスピーカー、空の行がフック、`#` だけの行が「＃」である。
// 呼び出し音とランプはターミナルの文字で、読み上げた文もターミナルに書く。イヤホンを付けて使う。
// Linux では、電話機の受話器とフックとキーパッドと呼び出し音を使い、ランプはログだけを書く。
// 部品の確認は、電話機の上で `device check devices|speaker|mic|hook|ringer|keypad` である。
//
// 見守る方を渡さずに起動した電話機は、自分の ID と鍵を作り、合言葉で登録してからそれでつなぐ。
// 結び付きができるまでは待ち、結び付いた見守る方の電話を受ける。
// --watched-person を付けた電話機は、今までどおり共通の合言葉で、その見守る方につながる。
// Pi では、環境変数 KAZOKUAI_WATCHED_PERSON が空のときが、ID と鍵のつなぎ方である。
// ID と鍵のファイルは --phone-file か KAZOKUAI_PHONE_FILE で変える。
// 空なら、Pi は /var/lib/kazokuai/phone.json、Mac はユーザーの設定ディレクトリである。
// バックエンドの URL は --backend で渡す。既定は http://localhost:8080 で、https は wss でつなぐ。
// 合言葉は環境変数 PHONE_SECRET から読む。前後の空白は除く。未設定なら開発用の合言葉を使う。
// 電話機の音声とフックは環境変数から読む。空なら受話器の配線の既定である。
// device check は /etc/kazokuai/device.env があれば読み、空の環境変数も含めて上書きする。
//
//	mise run device
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
	opts, err := parseArgs(args, os.Getenv)
	if err != nil {
		return err
	}
	var identity phone.Identity
	if opts.person == "" {
		path := opts.phoneFile
		if path == "" {
			path, err = phone.DefaultIdentityPath()
			if err != nil {
				return err
			}
		}
		identity, err = phone.LoadOrCreateIdentity(path)
		if err != nil {
			return err
		}
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()

	opened, cleanup, err := openPhone(os.Stdout)
	if err != nil {
		return err
	}
	defer cleanup()

	device := &phone.Device{
		Backend: opts.backend,
		Secret:  phoneSecret(os.Getenv("PHONE_SECRET")),
		Gemini:  liveAPI{},
		Phone:   opened,
		Out:     os.Stdout,
		Clock:   realClock{},
		Echo:    echoesSpeech(),
	}
	if opts.person == "" {
		device.ID = identity.ID
		device.Key = identity.Key
	} else {
		device.WatchedPerson = opts.person
	}
	if err := device.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
		return fmt.Errorf("電話機が終わりました: %w", err)
	}
	return nil
}

// runOptions は、起動の引数と環境変数から決めた電話機のつなぎ方である。
type runOptions struct {
	person    string
	backend   string
	phoneFile string
}

// parseArgs は、--watched-person、--backend、--phone-file を読む。
// 見守る方のフラグが空なら、環境変数 KAZOKUAI_WATCHED_PERSON を使う。それも空なら、ID と鍵でつなぐ。
// ファイルのフラグが空なら、KAZOKUAI_PHONE_FILE を使う。それも空なら、呼び出し側が既定の場所を使う。
func parseArgs(args []string, getenv func(string) string) (runOptions, error) {
	if getenv == nil {
		getenv = func(string) string { return "" }
	}
	fs := flag.NewFlagSet("device", flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	id := fs.String("watched-person", "", "見守る方の ID。空なら、電話機の ID と鍵でつなぐ")
	backendURL := fs.String("backend", "http://localhost:8080", "バックエンドの URL。https は wss でつなぐ")
	file := fs.String("phone-file", "", "ID と鍵のファイル。空なら、Pi は /var/lib/kazokuai/phone.json、Mac は設定ディレクトリ")
	if err := fs.Parse(args); err != nil {
		return runOptions{}, err
	}
	if strings.TrimSpace(*backendURL) == "" {
		return runOptions{}, errors.New("バックエンドの URL が要ります。--backend で渡してください")
	}
	person := strings.TrimSpace(*id)
	if person == "" {
		person = strings.TrimSpace(getenv("KAZOKUAI_WATCHED_PERSON"))
	}
	phoneFile := strings.TrimSpace(*file)
	if phoneFile == "" {
		phoneFile = strings.TrimSpace(getenv(phone.PhoneFileEnv))
	}
	return runOptions{person: person, backend: *backendURL, phoneFile: phoneFile}, nil
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

// phoneSecret は、環境変数の合言葉を返す。前後の空白は除く。未設定なら開発用の合言葉である。
func phoneSecret(env string) string {
	if secret := strings.TrimSpace(env); secret != "" {
		return secret
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
