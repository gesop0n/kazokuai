package phone

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gesop0n/kazokuai/device/spoken"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

const (
	// hashKey は、認証コードを頼むキーである。キーパッドの「＃」も、Mac の `#` だけの行も、この文字で届く。
	hashKey = "#"
	// starKey は、見守る方からの電話を始めるキーである。キーパッドの「＊」も、Mac の `*` だけの行も、この文字で届く。
	starKey = "*"
)

// starRequestTimeout は、「＊」の頼みを待つ上限である。止まっても、このあと「＊」をやり直せる。
const starRequestTimeout = 10 * time.Second

const (
	lineOffline   = "インターネットにつながっていません。Wi-Fi を確かめてください。"
	lineFailed    = "うまくいきませんでした。しばらくしてから、もう一度シャープを押してください。"
	lineCompleted = "同期が完了しました。受話器を置いてください。"
)

// speech は、受話器で流す文である。gen が頼んだときの番号と違うときは、もう流さない。
// code は、認証コードの読み上げである。話しているあいだの「＊」は捨てる。
type speech struct {
	gen  int
	pcm  []byte
	line string
	code bool
}

// idleUntilCall は、電話が来るまでフックとキーパッドを見る。
// 受話器を上げただけでは何も流さない。上がっているときの「＃」で認証コードを頼み、置くと音声を止める。
// 上がっていて電話の最中でなく、認証コードを話していないときの「＊」で、電話を始める。
func (d *Device) idleUntilCall(ctx context.Context, commands *callQueue) (queuedCall, bool) {
	if call, ok := d.takeCall(ctx, commands); ok || ctx.Err() != nil {
		return call, ok
	}
	var events <-chan HookEvent
	if d.Phone.Hook != nil {
		d.Phone.Hook.Prepare()
		defer d.Phone.Hook.Rest()
		events = d.Phone.Hook.Events()
		d.adoptHandset()
	}
	keys := d.keys()
	for {
		if call, ok := d.takeCall(ctx, commands); ok || ctx.Err() != nil {
			return call, ok
		}
		select {
		case <-ctx.Done():
			return queuedCall{}, false
		case <-commands.wake:
		case ev, ok := <-events:
			if !ok {
				events = nil
				continue
			}
			d.onHook(ev)
		case key, ok := <-keys:
			if !ok {
				keys = nil
				continue
			}
			d.onKey(ctx, commands, key)
		case spoken := <-d.speeches:
			d.onSpeech(spoken)
		}
	}
}

func (d *Device) takeCall(ctx context.Context, commands *callQueue) (queuedCall, bool) {
	if ctx.Err() != nil {
		return queuedCall{}, false
	}
	return commands.try()
}

func (d *Device) keys() <-chan string {
	if d.Phone.Keypad == nil {
		return nil
	}
	return d.Phone.Keypad.Keys()
}

// discardKeys は、電話の準備と通話のあいだに押したキーを捨てる。
// 戻った関数は、その捨てるのをやめて、残ったキーも捨てる。
func (d *Device) discardKeys() func() {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		keys := d.keys()
		if keys == nil {
			return
		}
		for {
			select {
			case <-ctx.Done():
				return
			case _, ok := <-keys:
				if !ok {
					return
				}
			}
		}
	}()
	return func() {
		cancel()
		<-done
		d.drainKeys()
	}
}

// drainKeys は、捨てる側が止まった直後にチャネルへ残ったキーを捨てる。
func (d *Device) drainKeys() {
	keys := d.keys()
	if keys == nil {
		return
	}
	for {
		select {
		case _, ok := <-keys:
			if !ok {
				return
			}
		default:
			return
		}
	}
}

// adoptHandset は、監視を切り替えるときに、受話器が今上がっているかを覚え直す。
// すでに上がっている受話器は、上がった出来事にならない。
func (d *Device) adoptHandset() {
	if d.Phone.Hook == nil {
		return
	}
	up := d.Phone.Hook.Lifted()
	d.mu.Lock()
	d.handsetUp = up
	d.mu.Unlock()
}

func (d *Device) onHook(ev HookEvent) {
	d.noteHook(ev)
	if ev == PutDown {
		d.hush()
	}
}

// noteHook は、受話器が上がっているかを覚え、置かれたら今の読み上げを捨てる。
func (d *Device) noteHook(ev HookEvent) {
	d.mu.Lock()
	defer d.mu.Unlock()
	switch ev {
	case PickedUp:
		d.handsetUp = true
	case PutDown:
		d.handsetUp = false
		d.speakGen++
		d.readingCode = false
		d.codeGen++
		d.voicing = false
	}
}

func (d *Device) onKey(ctx context.Context, commands *callQueue, key string) {
	switch key {
	case hashKey:
		d.onHash(ctx)
	case starKey:
		d.onStar(ctx, commands)
	}
}

func (d *Device) onHash(ctx context.Context) {
	d.mu.Lock()
	up := d.handsetUp
	var gen int
	if up {
		d.speakGen++
		gen = d.speakGen
	}
	d.mu.Unlock()
	if !up {
		return
	}
	d.hush()
	go d.fetchCode(ctx, gen)
}

// onStar は、受話器が上がっていて、電話の最中でなく、認証コードを話していないときだけ、電話を頼む。
func (d *Device) onStar(ctx context.Context, commands *callQueue) {
	d.mu.Lock()
	if !d.handsetUp || d.calling || d.readingCode || d.starBusy {
		d.mu.Unlock()
		return
	}
	d.starBusy = true
	d.speakGen++
	gen := d.speakGen
	d.mu.Unlock()
	d.hush()
	go d.fetchOwnCall(ctx, commands, gen)
}

func (d *Device) onSpeech(s speech) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if s.gen != d.speakGen || !d.handsetUp || d.calling || len(s.pcm) == 0 {
		return
	}
	if s.code {
		d.readingCode = true
		d.codeGen = s.gen
		d.armCodeTimer(s.gen, s.pcm)
	}
	d.voicing = true
	d.say(s.pcm, s.line)
}

// armCodeTimer は、認証コードを話し終えるころに、読み上げ中の印を外す。
func (d *Device) armCodeTimer(gen int, pcm []byte) {
	wait := codeDuration(pcm)
	if wait <= 0 || d.Clock == nil {
		return
	}
	timer := d.Clock.NewTimer(wait)
	go func() {
		<-timer.Chan()
		d.mu.Lock()
		if d.codeGen == gen {
			d.readingCode = false
		}
		d.mu.Unlock()
	}()
}

func codeDuration(pcm []byte) time.Duration {
	samples := len(pcm) / 2
	if samples <= 0 {
		return 0
	}
	return time.Duration(samples) * time.Second / SpeakerSampleRate
}

// deliverSynced は、同期済みになった知らせを、今の受話器の状態で扱う。
// 上がっていて電話の最中でないときだけ、完了の文を流す。
func (d *Device) deliverSynced() {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.calling || !d.handsetUp {
		return
	}
	d.speakGen++
	d.readingCode = false
	d.codeGen++
	d.voicing = true
	d.hush()
	d.say(spoken.Completed(), lineCompleted)
}

// stopSpeaking は、電話が始まるので、今の読み上げを止める。
func (d *Device) stopSpeaking() {
	d.mu.Lock()
	voicing := d.voicing
	d.speakGen++
	d.readingCode = false
	d.codeGen++
	d.voicing = false
	d.mu.Unlock()
	// 流していないときに止めると、偽の受話器が回数を増やし、通話中の割り込みの回数と重なる。
	if voicing {
		d.hush()
	}
}

func (d *Device) hush() {
	if d.Phone.Handset != nil {
		d.Phone.Handset.Hush()
	}
}

func (d *Device) say(pcm []byte, line string) {
	if d.Echo && line != "" && d.Out != nil {
		fmt.Fprintln(d.Out, line)
	}
	if d.Phone.Handset != nil && len(pcm) > 0 {
		d.Phone.Handset.Play(pcm)
	}
}

func (d *Device) setCalling(v bool) {
	d.mu.Lock()
	d.calling = v
	if v {
		d.starBusy = false
		d.readingCode = false
		d.codeGen++
	}
	d.mu.Unlock()
}

func (d *Device) fetchCode(ctx context.Context, gen int) {
	pcm, line, code := d.askCode(ctx)
	select {
	case <-ctx.Done():
	case d.speeches <- speech{gen: gen, pcm: pcm, line: line, code: code}:
	}
}

// fetchOwnCall は、バックエンドに電話を頼む。始まったら、その ID を電話の列へ入れる。
// 断られたときと、届かないときは、今の読み上げとしてエラーの文を流す。
func (d *Device) fetchOwnCall(ctx context.Context, commands *callQueue, gen int) {
	id, pcm, line := d.askOwnCall(ctx)
	if id != "" {
		commands.pushOwn(id)
		return
	}
	d.mu.Lock()
	d.starBusy = false
	up := d.handsetUp
	current := d.speakGen
	d.mu.Unlock()
	if !up || current != gen || len(pcm) == 0 {
		return
	}
	select {
	case <-ctx.Done():
	case d.speeches <- speech{gen: gen, pcm: pcm, line: line}:
	}
}

// askOwnCall は、バックエンドに見守る方からの電話を頼む。
// 届かなければインターネットの文、断られたら失敗の文を返す。始まったときは、電話の ID を返す。
func (d *Device) askOwnCall(ctx context.Context) (string, []byte, string) {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	timer := d.Clock.NewTimer(starRequestTimeout)
	defer timer.Stop()
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-timer.Chan():
			cancel()
		case <-ctx.Done():
		case <-done:
		}
	}()
	resp, err := d.postBackend(ctx, protocol.PhoneCallPath, nil)
	if err != nil {
		log.Printf("電話を始められなかった: %v", err)
		return "", spoken.Offline(), lineOffline
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode != http.StatusCreated {
		log.Printf("電話の答えが %s だった", resp.Status)
		return "", spoken.Failed(), lineFailed
	}
	var started protocol.StartedCall
	if json.Unmarshal(raw, &started) != nil || started.ID == "" {
		log.Printf("電話の ID を読めなかった")
		return "", spoken.Failed(), lineFailed
	}
	return started.ID, nil, ""
}

// askCode は、バックエンドに認証コードを頼む。
// 届かなければインターネットの文、エラーなら失敗の文、同期の準備が無ければ何も返さない。
// code は、返した音声が認証コードの読み上げであるとき真である。
func (d *Device) askCode(ctx context.Context) (pcm []byte, line string, code bool) {
	resp, err := d.postBackend(ctx, protocol.PhoneCodePath, nil)
	if err != nil {
		log.Printf("認証コードをもらえなかった: %v", err)
		return spoken.Offline(), lineOffline, false
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode == http.StatusConflict && strings.Contains(string(raw), protocol.PhoneAnswerSyncClosed) {
		return nil, "", false
	}
	if resp.StatusCode != http.StatusOK {
		log.Printf("認証コードの答えが %s だった", resp.Status)
		return spoken.Failed(), lineFailed, false
	}
	var payload struct {
		Code string `json:"code"`
	}
	if json.Unmarshal(raw, &payload) != nil {
		log.Printf("認証コードの答えを読めなかった")
		return spoken.Failed(), lineFailed, false
	}
	pcm, err = spoken.Code(payload.Code)
	if err != nil {
		log.Printf("認証コードを読めなかった: %v", err)
		return spoken.Failed(), lineFailed, false
	}
	return pcm, codeLine(payload.Code), true
}

// codeLine は、認証コードを 2 回読む文である。数字のあいだは読点で、例は仕様書の 482751。
func codeLine(digits string) string {
	parts := make([]string, len(digits))
	for i := 0; i < len(digits); i++ {
		parts[i] = digits[i : i+1]
	}
	spokenDigits := strings.Join(parts, "、")
	return "認証コードは、" + spokenDigits + " です。もう一度お伝えします。" + spokenDigits + " です。"
}
