package phone

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode"

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
	// 報告の送信は、後始末の defer より先に登録する。
	// defer は登録の逆順に動くので、送信はマイクを止め、まだ流していない音を捨て、接続を閉じ、ランプを消したあとに行われる。
	// 送信は最大 reportTimeout 待つ。そのあいだ受話器の後始末を残すと、置いたあとも音声が流れ、ランプが点いたままになる。
	var pending *protocol.CallReport
	defer func() {
		if pending == nil {
			return
		}
		if err := d.sendReport(*pending); err != nil {
			// 送れなかった電話は、送り直さない。ターミナルに理由だけ出す。
			fmt.Fprintf(d.Out, "電話の報告を送れなかった: %v\n", err)
		}
	}()

	token, err := d.fetchToken(ctx)
	if err != nil {
		return fmt.Errorf("短命トークンをもらえなかった: %w", err)
	}
	session, err := d.Gemini.Connect(ctx, token.Token, token.Model)
	if err != nil {
		return fmt.Errorf("Live API につなげなかった: %w", err)
	}
	done := make(chan struct{})
	var ended sync.Once
	endSession := func() {
		ended.Do(func() {
			close(done)
			session.Close()
		})
	}
	defer endSession()
	received, lost := receive(session, done)
	outgoing, turns, unsent := send(session, done)

	d.Phone.Lamp.On()
	// ランプを消すのは、下の後始末で 1 回だけである。ここに defer を足すと、報告の前と後で 2 回消える。
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
		if !lines.pickedUp.IsZero() {
			built := lines.report(d.Clock.Now())
			pending = &built
		}
		closeMic()
		d.Phone.Handset.Hush()
		endSession()
		d.Phone.Lamp.Off()
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
		lines.addInput(in.Text, in.Finished)
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
	// 終わりの印がなくても、モデルが話し終えたら、そこまでの AI の発話は 1 行である。
	// 出力の文字起こしは、この印より先に届く。
	if content.GenerationComplete {
		lines.modelTurnCompleted()
	}
	// 割り込まれたターンには、モデルが話し終えた印は来ない。そこまでの AI の発話を区切る。
	// 出力の文字起こしは、この印より先に届く。見守る方の発話は、ここでは区切らない。
	if content.Interrupted {
		lines.flushOutput()
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
// AI の行を区切るのは、その文字起こしが終わったとき、モデルが話し終えたとき、話に割り込まれたとき、電話が終わったときである。
// 見守る方の行を区切るのは、その文字起こしが終わったとき、モデルが話し終えたあとに終わりの印のない次の発話が届いたとき、電話が終わったときである。
// 終わりの印が付いた欠片は、モデルの通知より遅れても、開いている発話の末尾である。
// 相手の文字起こしや TurnComplete では区切らない。入り交じって届いた欠片は、1 つの発話のままである。
type transcript struct {
	out   io.Writer
	clock Clock
	// pickedUp は、受話器を上げた時刻である。ゼロなら、まだ上がっていない。
	pickedUp time.Time
	// input は見守る方の声の文字起こし、output は AI の声の文字起こしである。
	input, output openLine
	// seq は、開いている行が始まった順番を数える。電話の終わりに、先に始まった行から出す。
	seq int
	// modelTurns は、モデルが話し終えた回数である。見守る方の次の発話を、前の発話と分けるのに使う。
	modelTurns int
	// recorded は、区切った発話と、それが始まった順番である。
	// 文字起こしが終わる順に増える。報告の直前に、始まった順へ並べる。
	recorded []recordedUtterance
}

// recordedUtterance は、区切った 1 つの発話と、その発話が始まった順番である。
type recordedUtterance struct {
	seq       int
	utterance protocol.Utterance
}

// openLine は、まだ区切っていない 1 人の文字起こしである。
type openLine struct {
	text strings.Builder
	// seq は、この行が始まった順番である。0 なら、この行は空である。
	seq int
	// at は、この行の最初の文字が届いた時刻である。
	at time.Time
	// modelTurns は、この行が始まったときに、モデルが話し終えていた回数である。
	modelTurns int
}

// addInput は、見守る方の文字起こしを開いている行へ足す。
// finished は、この欠片がその発話の終わりの印を持つかである。
// 終わりの印は、モデルが話し終えた通知と到着順が決まっていない。印の付いた欠片は、開いている発話の末尾である。
// 印のない欠片が、モデルが話し終えたあとに届いたときだけ、次の発話として前の行を区切る。
func (t *transcript) addInput(chunk string, finished bool) {
	if !finished && t.input.text.Len() > 0 && t.modelTurns > t.input.modelTurns {
		t.flushInput()
	}
	t.add(&t.input, chunk)
}

func (t *transcript) addOutput(chunk string) { t.add(&t.output, chunk) }

// modelTurnCompleted は、モデルが話し終えたので、開いている AI の発話を区切る。
func (t *transcript) modelTurnCompleted() {
	t.flushOutput()
	t.modelTurns++
}

func (t *transcript) add(line *openLine, chunk string) {
	if line.text.Len() == 0 {
		t.seq++
		line.seq = t.seq
		line.at = t.clock.Now()
		line.modelTurns = t.modelTurns
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
	text := strings.TrimSpace(tightenJapanese(line.text.String()))
	at := line.at
	seq := line.seq
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
	t.recorded = append(t.recorded, recordedUtterance{
		seq: seq,
		utterance: protocol.Utterance{
			Speaker:  speaker,
			OffsetMs: offset.Milliseconds(),
			Text:     text,
		},
	})
}

// tightenJapanese は、かな、漢字、句読点の間にある空白を除く。
// ラテン文字の単語の間の空白は残す。文字起こしは「朝に おにぎり」のように空白を挟む。
func tightenJapanese(text string) string {
	rs := []rune(text)
	var b strings.Builder
	var prev rune
	hasPrev := false
	for i := 0; i < len(rs); {
		if unicode.IsSpace(rs[i]) {
			j := i
			for j < len(rs) && unicode.IsSpace(rs[j]) {
				j++
			}
			if hasPrev && j < len(rs) && isJapanese(prev) && isJapanese(rs[j]) {
				i = j
				continue
			}
			b.WriteString(string(rs[i:j]))
			prev = rs[j-1]
			hasPrev = true
			i = j
			continue
		}
		b.WriteRune(rs[i])
		prev = rs[i]
		hasPrev = true
		i++
	}
	return b.String()
}

func isJapanese(r rune) bool {
	switch {
	case r >= 0x3040 && r <= 0x309F, // ひらがな
		r >= 0x30A0 && r <= 0x30FF, // カタカナ
		r >= 0x3400 && r <= 0x4DBF, // CJK 拡張 A
		r >= 0x4E00 && r <= 0x9FFF, // 漢字
		r >= 0xFF66 && r <= 0xFF9D: // 半角カナ
		return true
	}
	switch r {
	case '、', '。', '「', '」', '『', '』', '（', '）', '！', '？', '〜', '…', '々', '〆', '・', '：', '；':
		return true
	default:
		return false
	}
}

// report は、この電話の報告を作る。ended は、電話が終わった時刻である。
func (t *transcript) report(ended time.Time) protocol.CallReport {
	duration := ended.Sub(t.pickedUp)
	if duration < 0 {
		duration = 0
	}
	// 先に始まった発話を先にする。文字起こしが先に終わった発話が、会話の前に来ないようにする。
	slices.SortFunc(t.recorded, func(a, b recordedUtterance) int { return a.seq - b.seq })
	utterances := make([]protocol.Utterance, len(t.recorded))
	for i, item := range t.recorded {
		utterances[i] = item.utterance
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
