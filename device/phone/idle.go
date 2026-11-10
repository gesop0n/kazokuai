package phone

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"

	"github.com/gesop0n/kazokuai/device/spoken"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// hashKey は、認証コードを頼むキーである。キーパッドの「＃」も、Mac の `#` だけの行も、この文字で届く。
const hashKey = "#"

const (
	lineOffline   = "インターネットにつながっていません。Wi-Fi を確かめてください。"
	lineFailed    = "うまくいきませんでした。しばらくしてから、もう一度シャープを押してください。"
	lineCompleted = "同期が完了しました。受話器を置いてください。"
)

// speech は、認証コードを頼んだ結果である。gen が頼んだときの番号と違うときは、もう流さない。
type speech struct {
	gen  int
	pcm  []byte
	line string
}

// idleUntilCall は、電話が来るまでフックとキーパッドを見る。
// 受話器を上げただけでは何も流さない。上がっているときの「＃」で認証コードを頼み、置くと音声を止める。
func (d *Device) idleUntilCall(ctx context.Context, commands *callQueue) (string, bool) {
	if id, ok := d.takeCall(ctx, commands); ok || ctx.Err() != nil {
		return id, ok
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
		if id, ok := d.takeCall(ctx, commands); ok || ctx.Err() != nil {
			return id, ok
		}
		select {
		case <-ctx.Done():
			return "", false
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
			d.onKey(ctx, key)
		case spoken := <-d.speeches:
			d.onSpeech(spoken)
		}
	}
}

func (d *Device) takeCall(ctx context.Context, commands *callQueue) (string, bool) {
	if ctx.Err() != nil {
		return "", false
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
// すでに上がっている受話器を置いても、Pi の接点は置いた出来事を出さない。
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
	}
}

func (d *Device) onKey(ctx context.Context, key string) {
	if key != hashKey {
		return
	}
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

func (d *Device) onSpeech(s speech) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if s.gen != d.speakGen || !d.handsetUp || d.calling || len(s.pcm) == 0 {
		return
	}
	d.say(s.pcm, s.line)
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
	d.hush()
	d.say(spoken.Completed(), lineCompleted)
}

// stopSpeaking は、電話が始まるので、今の読み上げを止める。
func (d *Device) stopSpeaking() {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.speakGen++
	d.hush()
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
	d.mu.Unlock()
}

func (d *Device) fetchCode(ctx context.Context, gen int) {
	pcm, line := d.askCode(ctx)
	select {
	case <-ctx.Done():
	case d.speeches <- speech{gen: gen, pcm: pcm, line: line}:
	}
}

// askCode は、バックエンドに認証コードを頼む。
// 届かなければインターネットの文、エラーなら失敗の文、同期の準備が無ければ何も返さない。
func (d *Device) askCode(ctx context.Context) ([]byte, string) {
	resp, err := d.postBackend(ctx, protocol.PhoneCodePath, nil)
	if err != nil {
		log.Printf("認証コードをもらえなかった: %v", err)
		return spoken.Offline(), lineOffline
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode == http.StatusConflict && strings.Contains(string(raw), protocol.PhoneAnswerSyncClosed) {
		return nil, ""
	}
	if resp.StatusCode != http.StatusOK {
		log.Printf("認証コードの答えが %s だった", resp.Status)
		return spoken.Failed(), lineFailed
	}
	var payload struct {
		Code string `json:"code"`
	}
	if json.Unmarshal(raw, &payload) != nil {
		log.Printf("認証コードの答えを読めなかった")
		return spoken.Failed(), lineFailed
	}
	pcm, err := spoken.Code(payload.Code)
	if err != nil {
		log.Printf("認証コードを読めなかった: %v", err)
		return spoken.Failed(), lineFailed
	}
	return pcm, codeLine(payload.Code)
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
