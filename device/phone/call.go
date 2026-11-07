package phone

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// Device は、バックエンドからトークンをもらい、電話機で電話をする。
type Device struct {
	// Backend は、バックエンドのベースの URL である。例: http://localhost:8080
	Backend string
	Gemini  Gemini
	Phone   Phone
	// Out は、開発者が見るターミナルである。両方の文字起こしを 1 行ずつ書く。
	Out io.Writer
	// Clock は、呼び出しの上限と電話の長さを測る。
	Clock Clock
}

// errNoAnswer は、呼び出しの上限を過ぎても受話器が上がらなかったときである。
var errNoAnswer = errors.New("見守る方が出ませんでした")

// Call は 1 回の電話をする。呼び出しを始め、受話器が置かれたときと、電話の長さの上限に達したときは nil を返す。
// 見守る方が出なかったとき、接続が切れたとき、サーバーが GoAway を送ってきたときは、その理由をエラーで返す。
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
	outgoing, turns, unsent := send(session, done)

	d.Phone.Lamp.On()
	defer d.Phone.Lamp.Off()
	// 呼び出し音を出す前に測り始める。テストは音が鳴ったのを見てから時計を進める。
	ringTimer := d.Clock.NewTimer(token.Times.RingTimeout)
	defer ringTimer.Stop()
	ringC := ringTimer.Chan()
	d.Phone.Ringer.Ring()
	ringing := true
	defer func() {
		if ringing {
			d.Phone.Ringer.Stop()
		}
	}()
	var wrapUpTimer, limitTimer Timer
	defer func() {
		if wrapUpTimer != nil {
			wrapUpTimer.Stop()
		}
		if limitTimer != nil {
			limitTimer.Stop()
		}
	}()
	var wrapUpC, limitC <-chan time.Time

	micCtx, closeMic := context.WithCancel(ctx)
	defer closeMic()
	// 受話器が上がるまでは nil なので、マイクの音を待たない
	var mic <-chan []byte
	lines := &transcript{out: d.Out, clock: d.Clock}
	defer func() {
		lines.flush()
		if lines.pickedUp.IsZero() {
			return
		}
		if err := d.sendReport(lines.report(d.Clock.Now())); err != nil {
			// 送れなかった電話は、送り直さない。ターミナルに理由だけ出す。
			fmt.Fprintf(d.Out, "電話の報告を送れなかった: %v\n", err)
		}
	}()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()

		case <-ringC:
			return errNoAnswer

		case <-wrapUpC:
			wrapUpC = nil
			cue := clientText(protocol.WrapUpCue(token.Times.WrapUpBefore))
			// 文字の発話用の口は空いているので、ここで待つことはない
			turns <- func(s Session) error { return s.SendClientContent(cue) }

		case <-limitC:
			return nil

		case event := <-d.Phone.Hook.Events():
			switch {
			case event == PickedUp && ringing:
				ringing = false
				lines.pickedUp = d.Clock.Now()
				d.Phone.Ringer.Stop()
				ringTimer.Stop()
				ringC = nil
				untilCue := token.Times.MaxCall - token.Times.WrapUpBefore
				if untilCue < 0 {
					untilCue = 0
				}
				wrapUpTimer = d.Clock.NewTimer(untilCue)
				limitTimer = d.Clock.NewTimer(token.Times.MaxCall)
				wrapUpC = wrapUpTimer.Chan()
				limitC = limitTimer.Chan()
				if mic, err = d.Phone.Handset.Listen(micCtx); err != nil {
					return fmt.Errorf("マイクを開けなかった: %w", err)
				}
				// 受話器が上がるまでは何も送らないので、turns は空で、ここで待つことはない
				turns <- func(s Session) error { return s.SendClientContent(startCue) }
			case event == PutDown && !ringing:
				return nil
			}

		case pcm, ok := <-mic:
			if !ok {
				mic = nil
				continue
			}
			audio := genai.LiveRealtimeInput{Audio: &genai.Blob{MIMEType: micMIMEType, Data: pcm}}
			select {
			case outgoing <- func(s Session) error { return s.SendRealtimeInput(audio) }:
			default:
				// 回線が詰まっていて送るのが追いつかないので、遅れた音は捨てる
			}

		case err := <-unsent:
			return fmt.Errorf("Live API に送れなかった: %w", err)

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
	if in := content.InputTranscription; in != nil {
		lines.addInput(in.Text)
		if in.Finished {
			lines.flushInput()
		}
	}
	if content.ModelTurn != nil {
		for _, part := range content.ModelTurn.Parts {
			if part.InlineData != nil && strings.HasPrefix(part.InlineData.MIMEType, "audio/pcm") {
				d.Phone.Handset.Play(part.InlineData.Data)
			}
		}
	}
	if out := content.OutputTranscription; out != nil {
		lines.addOutput(out.Text)
		if out.Finished {
			lines.flushOutput()
		}
	}
	if content.Interrupted {
		d.Phone.Handset.Hush()
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

// send は、outgoing に入れた音声と、turns に入れた文字の発話を、Live のセッションで送る。
// 文字の発話は音声より先に送る。締めの合図が、溜まった音声の後ろで遅れないようにするためである。
// 書き込みは回線が止まると戻らないので、電話の処理とは別の goroutine で行い、そのあいだも受話器を置けるようにする。
// 電話が終わってセッションを閉じると、止まっている書き込みも戻る。書き込めなかったら、その理由を unsent に送って終わる。
func send(session Session, done <-chan struct{}) (outgoing, turns chan<- func(Session) error, unsent <-chan error) {
	audio := make(chan func(Session) error, 64)
	text := make(chan func(Session) error, 2)
	errs := make(chan error, 1)
	go func() {
		for {
			var write func(Session) error
			select {
			case <-done:
				return
			case write = <-text:
			default:
				select {
				case <-done:
					return
				case write = <-text:
				case write = <-audio:
				}
			}
			if err := write(session); err != nil {
				errs <- err
				return
			}
		}
	}()
	return audio, text, errs
}

// transcript は、少しずつ届く文字起こしを話し手ごとにまとめ、ターミナルに 1 行ずつ出す。
// 行を区切るのは、その人の文字起こしが終わったときと、電話が終わったときだけである。
// 相手の文字起こしや TurnComplete では区切らない。入り交じって届いても、1 つの発話は 1 行のままになる。
type transcript struct {
	out   io.Writer
	clock Clock
	// pickedUp は、受話器を上げた時刻である。ゼロなら、まだ上がっていない。
	pickedUp time.Time
	// input は見守る方の声の文字起こし、output は AI の声の文字起こしである。
	input, output openLine
	// seq は、開いている行が始まった順番を数える。電話の終わりに、先に始まった行から出す。
	seq int
	// utterances は、区切った発話を、区切った順に持つ。
	utterances []protocol.Utterance
}

// openLine は、まだ区切っていない 1 人の文字起こしである。
type openLine struct {
	text strings.Builder
	// seq は、この行が始まった順番である。0 なら、この行は空である。
	seq int
	// at は、この行の最初の文字が届いた時刻である。
	at time.Time
}

func (t *transcript) addInput(chunk string)  { t.add(&t.input, chunk) }
func (t *transcript) addOutput(chunk string) { t.add(&t.output, chunk) }

func (t *transcript) add(line *openLine, chunk string) {
	if line.text.Len() == 0 {
		t.seq++
		line.seq = t.seq
		line.at = t.clock.Now()
	}
	line.text.WriteString(chunk)
}

func (t *transcript) flushInput()  { t.close("見守る方", protocol.SpeakerWatched, &t.input) }
func (t *transcript) flushOutput() { t.close("かぞくAI", protocol.SpeakerAI, &t.output) }

// flush は、電話の終わりに、まだ区切っていない行を、始まった順に出す。
func (t *transcript) flush() {
	switch {
	case t.input.text.Len() == 0:
		t.flushOutput()
	case t.output.text.Len() == 0:
		t.flushInput()
	case t.output.seq < t.input.seq:
		t.flushOutput()
		t.flushInput()
	default:
		t.flushInput()
		t.flushOutput()
	}
}

func (t *transcript) close(label, speaker string, line *openLine) {
	text := strings.TrimSpace(line.text.String())
	at := line.at
	line.text.Reset()
	line.seq = 0
	if text == "" {
		return
	}
	fmt.Fprintf(t.out, "%s: %s\n", label, text)
	if t.pickedUp.IsZero() {
		return
	}
	offset := at.Sub(t.pickedUp)
	if offset < 0 {
		offset = 0
	}
	t.utterances = append(t.utterances, protocol.Utterance{
		Speaker:  speaker,
		OffsetMs: offset.Milliseconds(),
		Text:     text,
	})
}

// report は、この電話の報告を作る。ended は、電話が終わった時刻である。
func (t *transcript) report(ended time.Time) protocol.CallReport {
	duration := ended.Sub(t.pickedUp)
	if duration < 0 {
		duration = 0
	}
	utterances := t.utterances
	if utterances == nil {
		utterances = []protocol.Utterance{}
	}
	return protocol.CallReport{
		StartedAt:  t.pickedUp,
		DurationMs: duration.Milliseconds(),
		Utterances: utterances,
	}
}

// micMIMEType は、Live API に送るマイクの音の形式である。
var micMIMEType = fmt.Sprintf("audio/pcm;rate=%d", MicSampleRate)

// clientText は、見守る方の発話として送る文字である。発話を終えてあるので、AI がそれに答えられる。
func clientText(text string) genai.LiveClientContentInput {
	return genai.LiveClientContentInput{
		Turns:        []*genai.Content{genai.NewContentFromText(text, genai.RoleUser)},
		TurnComplete: genai.Ptr(true),
	}
}

// startCue は、受話器が上がったときに送る始まりの合図である。
var startCue = clientText(protocol.StartCue)

// reportTimeout は、電話の報告を送るときに待つ上限である。失敗しても送り直さない。
const reportTimeout = 10 * time.Second

// sendReport は、終わった電話の報告をバックエンドに 1 回送る。
func (d *Device) sendReport(report protocol.CallReport) error {
	body, err := json.Marshal(report)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), reportTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, d.Backend+protocol.CallReportPath, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted {
		text, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("バックエンドが %s を返した: %s", resp.Status, text)
	}
	return nil
}

// fetchToken は、バックエンドからこの電話の短命トークンをもらう。
func (d *Device) fetchToken(ctx context.Context) (*protocol.TokenResponse, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, d.Backend+protocol.TokenPath, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
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
