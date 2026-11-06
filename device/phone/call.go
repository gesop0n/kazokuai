package phone

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// Device は、バックエンドからトークンをもらい、電話機で電話をする。
type Device struct {
	// Backend は、バックエンドのベースの URL である。例: http://localhost:8080
	Backend string
	// HTTPClient は、バックエンドを呼ぶクライアントである。nil なら http.DefaultClient を使う。
	HTTPClient *http.Client
	Gemini     Gemini
	Phone      Phone
	// Out は、開発者が見るターミナルである。両方の文字起こしを 1 行ずつ書く。
	Out io.Writer
}

// Call は 1 回の電話をする。呼び出しを始め、受話器が置かれたら nil を返す。
// ほかの理由で電話が終わったときは、その理由をエラーで返す。
func (d *Device) Call(ctx context.Context) error {
	token, err := d.fetchToken(ctx)
	if err != nil {
		return fmt.Errorf("短命トークンをもらえなかった: %w", err)
	}
	session, err := d.Gemini.Connect(ctx, token.Token, token.Model)
	if err != nil {
		return fmt.Errorf("Live API につなげなかった: %w", err)
	}
	defer session.Close()
	done := make(chan struct{})
	defer close(done)
	received, lost := receive(session, done)

	d.Phone.Lamp.On()
	defer d.Phone.Lamp.Off()
	d.Phone.Ringer.Ring()
	ringing := true
	defer func() {
		if ringing {
			d.Phone.Ringer.Stop()
		}
	}()

	micCtx, closeMic := context.WithCancel(ctx)
	defer closeMic()
	// 受話器が上がるまでは nil なので、マイクの音を待たない
	var mic <-chan []byte
	lines := &transcript{out: d.Out}
	defer lines.flush()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()

		case event := <-d.Phone.Hook.Events():
			switch {
			case event == PickedUp && ringing:
				ringing = false
				d.Phone.Ringer.Stop()
				if mic, err = d.Phone.Handset.Listen(micCtx); err != nil {
					return fmt.Errorf("マイクを開けなかった: %w", err)
				}
				if err := session.SendClientContent(startCue); err != nil {
					return fmt.Errorf("始まりの合図を送れなかった: %w", err)
				}
			case event == PutDown && !ringing:
				return nil
			}

		case pcm, ok := <-mic:
			if !ok {
				mic = nil
				continue
			}
			if err := session.SendRealtimeInput(genai.LiveRealtimeInput{
				Audio: &genai.Blob{MIMEType: micMIMEType, Data: pcm},
			}); err != nil {
				return fmt.Errorf("マイクの音を送れなかった: %w", err)
			}

		case msg := <-received:
			if msg.GoAway != nil {
				return fmt.Errorf("Live API のサーバーが GoAway で、残り %s で接続を終えると知らせてきた", msg.GoAway.TimeLeft)
			}
			d.hear(msg.ServerContent, lines)

		case err := <-lost:
			return fmt.Errorf("Live API との接続が切れた: %w", err)
		}
	}
}

// hear は、AI の音声を受話器で流し、両方の文字起こしを出す。
func (d *Device) hear(content *genai.LiveServerContent, lines *transcript) {
	if content == nil {
		return
	}
	if content.InputTranscription != nil {
		lines.elder.WriteString(content.InputTranscription.Text)
	}
	if content.ModelTurn != nil {
		for _, part := range content.ModelTurn.Parts {
			if part.InlineData != nil && strings.HasPrefix(part.InlineData.MIMEType, "audio/pcm") {
				d.Phone.Handset.Play(part.InlineData.Data)
			}
		}
	}
	if content.OutputTranscription != nil {
		// AI が話し始めたので、見守る方の話は終わっている
		lines.flushElder()
		lines.ai.WriteString(content.OutputTranscription.Text)
	}
	if content.Interrupted {
		d.Phone.Handset.Hush()
		lines.flushAI()
	}
	if content.TurnComplete {
		lines.flush()
	}
}

// receive は、Live のセッションから受け取ったメッセージを received に流す。
// 接続が切れると、その理由を lost に送って終わる。done が閉じたら、受け取っても流さずに終わる。
func receive(session Session, done <-chan struct{}) (received <-chan *genai.LiveServerMessage, lost <-chan error) {
	messages := make(chan *genai.LiveServerMessage)
	errs := make(chan error, 1)
	go func() {
		for {
			msg, err := session.Receive()
			if err != nil {
				errs <- err
				return
			}
			select {
			case messages <- msg:
			case <-done:
				return
			}
		}
	}()
	return messages, errs
}

// transcript は、少しずつ届く文字起こしを話し手ごとにまとめ、ターミナルに 1 行ずつ出す。
type transcript struct {
	out       io.Writer
	elder, ai strings.Builder
}

func (t *transcript) flushElder() { t.print("見守る方", &t.elder) }
func (t *transcript) flushAI()    { t.print("かぞくAI", &t.ai) }

func (t *transcript) flush() {
	t.flushElder()
	t.flushAI()
}

func (t *transcript) print(speaker string, text *strings.Builder) {
	if line := strings.TrimSpace(text.String()); line != "" {
		fmt.Fprintf(t.out, "%s: %s\n", speaker, line)
	}
	text.Reset()
}

// micMIMEType は、Live API に送るマイクの音の形式である。
const micMIMEType = "audio/pcm;rate=16000"

// startCue は、受話器が上がったときに見守る方の発話として送る始まりの合図である。
var startCue = genai.LiveClientContentInput{
	Turns:        []*genai.Content{genai.NewContentFromText(protocol.StartCue, genai.RoleUser)},
	TurnComplete: genai.Ptr(true),
}

// fetchToken は、バックエンドからこの電話の短命トークンをもらう。
func (d *Device) fetchToken(ctx context.Context) (*protocol.TokenResponse, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, d.Backend+protocol.TokenPath, nil)
	if err != nil {
		return nil, err
	}
	client := d.HTTPClient
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return nil, fmt.Errorf("バックエンドが %s を返した: %s", resp.Status, body)
	}
	var token protocol.TokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&token); err != nil {
		return nil, fmt.Errorf("バックエンドのレスポンスを読めなかった: %w", err)
	}
	return &token, nil
}
