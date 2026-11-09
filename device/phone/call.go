package phone

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// Device は、バックエンドとつながり続け、来た指示ごとに電話をする。
type Device struct {
	// Backend は、バックエンドのベースの URL である。例: http://localhost:8080。https は wss でつなぐ。
	Backend string
	// Secret は、バックエンドへ付ける合言葉である。
	Secret string
	// HTTP は、バックエンドへのクライアントである。nil なら http.DefaultClient を使う。
	// テストが、自分の証明を信じる TLS のバックエンドへつなぐときに渡す。
	HTTP *http.Client
	// WatchedPerson は、この電話機の見守る方の ID である。起動するときに渡す。
	WatchedPerson string
	Gemini        Gemini
	Phone         Phone
	// Out は、開発者が見るターミナルである。両方の文字起こしを 1 行ずつ書く。
	// 接続のつなぎ直しはここへ書かない。文字起こしの行と混ざる。
	Out io.Writer
	// Clock は、呼び出しの上限と電話の長さと、つなぎ直す間隔を測る。
	Clock Clock
	// AfterCall は、1 回の電話が終わったときに、そのエラーを渡して呼ぶ。本番は nil。
	// テストが、パッケージの外から電話の終わりを見るために使う。
	AfterCall func(error)

	mu         sync.Mutex
	cancelCall context.CancelFunc
	// stopping は、StopCall から、その電話を止めるまで真である。
	// 指示を読み取る直前に止めても、その電話を始めない。
	stopping bool
}

// errNoAnswer は、呼び出しの上限を過ぎても受話器が上がらなかったときである。
var errNoAnswer = errors.New("見守る方が出ませんでした")

// place は、callID の電話を 1 回する。受話器が置かれたときと、電話の長さの上限に達したときは nil を返す。
// 見守る方が出なかったとき、接続が切れたとき、サーバーが GoAway を送ってきたときは、その理由をエラーで返す。
// エラーで戻った電話は、受話器が上がっていても、つながらなかったである。
func (d *Device) place(ctx context.Context, link callLink, callID string) (err error) {
	// 待っているあいだの Enter を、この電話の受話器上げにしない。
	d.Phone.Hook.Prepare()
	// Rest を最初に登録する。defer は逆順なので、状態と報告を送り終えてからフックを戻す。
	defer d.Phone.Hook.Rest()

	// 報告の送信は、音声の後始末の defer より先に登録する。
	// 送信はマイクを止め、まだ流していない音を捨て、接続を閉じ、ランプを消したあとに行われる。
	// 送信は最大 reportTimeout 待つ。そのあいだ受話器の後始末を残すと、置いたあとも音声が流れ、ランプが点いたままになる。
	var pending *protocol.CallReport
	// 途中で失敗した電話は、つながらなかった。出なかったときは下で書き換える。
	// 受話器が上がって普通に終わったときだけ、終わったにする。
	endState := protocol.StateFailed
	defer func() {
		// 電話の context が取り消されたあとも、最後の状態は届ける。
		d.sendState(link, callID, endState)
		if pending == nil {
			return
		}
		if err := d.sendReport(*pending); err != nil {
			// 送れなかった電話は、送り直さない。ターミナルに理由だけ出す。
			fmt.Fprintf(d.Out, "電話の報告を送れなかった: %v\n", err)
		}
	}()

	token, err := d.fetchToken(ctx, callID)
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
	d.sendState(link, callID, protocol.StateRinging)
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
			built.CallID = callID
			built.WatchedPersonID = d.WatchedPerson
			pending = &built
			// 失敗で戻った電話は、受話器が上がっていても、つながらなかったのままにする。
			if err == nil {
				endState = protocol.StateEnded
			}
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
			endState = protocol.StateMissed
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
				// 送れなくても、電話そのものは続ける。最後の状態は、終わるときに改めて送る。
				d.sendState(link, callID, protocol.StateTalking)
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
			d.hear(msg, lines)

		case err := <-lost:
			return fmt.Errorf("Live API との接続が切れた: %w", err)
		}
	}
}

// hear は、AI の音声を受話器で流し、両方の文字起こしを出す。
// 話し始めは文字起こしより先に扱い、話し終わりは文字起こしのあとに扱う。
// 同じ知らせに両方が入っていても、その発話の文字は行に入る。
func (d *Device) hear(msg *genai.LiveServerMessage, lines *transcript) {
	if msg == nil {
		return
	}
	stop := false
	if msg.VoiceActivity != nil && !lines.pickedUp.IsZero() {
		if lines.speechStarted(msg.VoiceActivity) {
			lines.startSpeech(msg.VoiceActivity.AudioOffset)
		} else {
			stop = true
		}
	}
	content := msg.ServerContent
	if content != nil {
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
		// 終わりの印がなくても、モデルが話し終えたら、そこまでの AI の発話は 1 行である。
		// 出力の文字起こしは、この印より先に届く。見守る方の発話は、ここでは区切らない。
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
	if stop {
		lines.stopSpeech()
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
// 見守る方の行は、話し始めたときに始まり、話し終えたときか、電話が終わったときに区切る。時刻は、話し始めの音声の中の時刻である。
// 文字起こしに終わりの印が付いたときも区切る。相手の文字起こしや TurnComplete では区切らない。
// ひと続きの発話の欠片は、AI の文字起こしやモデルの知らせが間に入っても、1 行のままである。
type transcript struct {
	out   io.Writer
	clock Clock
	// pickedUp は、受話器を上げた時刻である。ゼロなら、まだ上がっていない。
	pickedUp time.Time
	// input は見守る方の声の文字起こし、output は AI の声の文字起こしである。
	input, output openLine
	// speaking は、見守る方が話し始めてから、話し終えるまでのあいだである。
	// 種類の空の音声活動を、話し始めと話し終わりに振り分ける。
	speaking bool
	// seq は、開いている行が始まった順番を数える。時刻が同じ発話は、この順に報告する。
	seq int
	// recorded は、区切った発話と、それが始まった順番である。
	// 区切った順に増える。報告の直前に、始まった時刻の順へ並べる。
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
	// at は、この行が始まった時刻である。
	// 見守る方は話し始めの音声の時刻、AI は最初の文字起こしが届いた時刻である。
	at time.Time
}

// speechStarted は、この音声活動が話し始めかを返す。
// genai の SDK v1.77.0 は、サーバーが type で送る種類を VoiceActivityType に入れない。
// 種類が空のときは、話しているあいだは話し終わり、そうでなければ話し始めである。
// 試しでは、ひと続きの発話ごとに、話し始めと話し終わりが交互に届いた。
func (t *transcript) speechStarted(activity *genai.VoiceActivity) bool {
	switch activity.VoiceActivityType {
	case genai.VoiceActivityTypeActivityStart:
		return true
	case genai.VoiceActivityTypeActivityEnd:
		return false
	default:
		return !t.speaking
	}
}

// startSpeech は、見守る方の発話を、音声の中の offset で始める。
// 時刻は、文字起こしが届いたときではなく、話し始めたときである。
func (t *transcript) startSpeech(offset time.Duration) {
	if t.speaking {
		t.flushInput()
	}
	t.speaking = true
	if t.input.seq != 0 {
		return
	}
	t.seq++
	t.input.seq = t.seq
	t.input.at = t.pickedUp.Add(offset)
}

// stopSpeech は、見守る方が話し終えたので、開いている発話を区切る。
func (t *transcript) stopSpeech() {
	t.speaking = false
	t.flushInput()
}

func (t *transcript) addInput(chunk string) { t.add(&t.input, chunk) }

func (t *transcript) addOutput(chunk string) { t.add(&t.output, chunk) }

// modelTurnCompleted は、モデルが話し終えたので、開いている AI の発話を区切る。
func (t *transcript) modelTurnCompleted() {
	t.flushOutput()
}

func (t *transcript) add(line *openLine, chunk string) {
	if line.seq == 0 {
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
	// 先に始まった発話を先にする。時刻が同じときは、始まりを扱った順にする。
	// 返答の文字起こしが先に届いても、見守る方の発話は、話し始めの時刻が早ければ前に来る。
	slices.SortFunc(t.recorded, func(a, b recordedUtterance) int {
		if a.utterance.OffsetMs != b.utterance.OffsetMs {
			if a.utterance.OffsetMs < b.utterance.OffsetMs {
				return -1
			}
			return 1
		}
		return a.seq - b.seq
	})
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
	resp, err := d.postBackend(ctx, protocol.CallReportPath, body)
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

// stateTimeout は、電話の状態を 1 通送るときに待つ上限である。
const stateTimeout = 5 * time.Second

// sendState は、電話の状態をバックエンドへ 1 通送る。
// その場で届かなくても、link が覚えていて、接続が戻ったときに送り直す。
// 文字起こしのターミナルには書かない。
func (d *Device) sendState(link callLink, callID, state string) {
	ctx, cancel := context.WithTimeout(context.Background(), stateTimeout)
	defer cancel()
	err := link.Send(ctx, protocol.PhoneMessage{
		Type:   protocol.PhoneTypeState,
		CallID: callID,
		State:  state,
	})
	if err != nil {
		log.Printf("電話の状態 %s を送れなかった: %v", state, err)
	}
}

// fetchToken は、バックエンドからこの電話の短命トークンをもらう。
func (d *Device) fetchToken(ctx context.Context, callID string) (*protocol.TokenResponse, error) {
	body, err := json.Marshal(protocol.TokenRequest{CallID: callID, WatchedPersonID: d.WatchedPerson})
	if err != nil {
		return nil, err
	}
	resp, err := d.postBackend(ctx, protocol.TokenPath, body)
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

func (d *Device) postBackend(ctx context.Context, path string, body []byte) (*http.Response, error) {
	endpoint, err := backendEndpoint(d.Backend, path)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set(protocol.PhoneSecretHeader, d.Secret)
	client := d.HTTP
	if client == nil {
		client = http.DefaultClient
	}
	return client.Do(req)
}

// backendEndpoint は、base の末尾の / に関わらず、path を 1 つの URL にする。
// base と path を文字列で足すと、末尾の / があるときに //token になり、ルートに届かない。
func backendEndpoint(base, path string) (string, error) {
	u, err := url.Parse(base)
	if err != nil {
		return "", err
	}
	ref, err := url.Parse(path)
	if err != nil {
		return "", err
	}
	return u.ResolveReference(ref).String(), nil
}
