// backend は、デバイスに短命トークンを渡し、アプリから見守る方の登録と今すぐ通話を受け、電話の報告からまとめを作るバックエンドのプログラムである。
// 電話をかける見守る方は、電話機が接続するときに渡す。名前と呼び方は、トークンを作るたびに Firestore から読む。
// Gemini の API キーは環境変数 GEMINI_API_KEY から読み、デバイスには渡さない。
// 0.0.0.0:$PORT で待つ。PORT が無ければ 8080 である。
// プロジェクトは環境変数 GOOGLE_CLOUD_PROJECT から読む。demo- のプロジェクトは Firebase のエミュレーターにつながり、
// それ以外は渡したプロジェクトのサービスアカウントでつながる。手元では mise run backend が demo-kazokuai とエミュレーターを渡す。
// 電話機の合言葉は環境変数 PHONE_SECRET から読む。demo- のプロジェクトで未設定なら、開発用の合言葉を使う。
// SIGTERM を受けると、電話機との接続を閉じてから止まる。
//
//	mise run backend
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/clock"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// 既定値と、Live API の接続の上限はここにまとめる。
// 接続は呼び出しが始まってから約 connectionLimit で切れる。
const (
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
	projectID, err := server.ResolveProject()
	if err != nil {
		return err
	}
	secret, err := server.SecretFor(projectID, os.Getenv("PHONE_SECRET"))
	if err != nil {
		return err
	}
	config.ProjectID = projectID
	config.PhoneSecret = secret
	addr, err := listenAddr(os.Getenv("PORT"))
	if err != nil {
		return err
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
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}
	handler := server.New(config, firebase, client.AuthTokens, client.Models, clock.Real{})
	log.Printf("%s で電話機の接続とトークンを受け、見守る方の登録と今すぐ通話と電話の報告を受けます。プロジェクト: %s、モデル: %s、声: %s、まとめ: %s", ln.Addr(), projectID, config.Model, config.Voice, config.SummaryModel)
	sigCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	return serve(sigCtx, ln, handler)
}

// listenAddr は、待ち受けるアドレスを返す。port が空なら 8080 である。どのインターフェースでも受ける。
func listenAddr(port string) (string, error) {
	if port == "" {
		port = "8080"
	}
	n, err := strconv.Atoi(port)
	if err != nil || n < 1 || n > 65535 {
		return "", fmt.Errorf("環境変数 PORT=%s は 1 から 65535 の番号にしてください", port)
	}
	return "0.0.0.0:" + strconv.Itoa(n), nil
}

// serve は、ln で handler を配る。ctx が終わると、電話機との接続を閉じてから戻る。
// SIGTERM は ctx を終わらせる。
func serve(ctx context.Context, ln net.Listener, handler *server.Handler) error {
	srv := &http.Server{Handler: handler}
	errc := make(chan error, 1)
	go func() {
		err := srv.Serve(ln)
		if errors.Is(err, http.ErrServerClosed) {
			err = nil
		}
		errc <- err
	}()
	select {
	case <-ctx.Done():
		handler.Stop()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
		return <-errc
	case err := <-errc:
		handler.Stop()
		return err
	}
}
