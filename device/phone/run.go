package phone

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

const (
	// reconnectMin は、切れてから次につなぐまでの最初の間隔である。
	reconnectMin = time.Second
	// reconnectMax は、つなぎ直す間隔の上限である。
	reconnectMax = 30 * time.Second
)

// callLink は、電話のあいだに状態を送る口である。WebSocket の接続を、電話の処理から隠す。
type callLink interface {
	Send(ctx context.Context, msg protocol.PhoneMessage) error
}

// wsLink は、1 本の WebSocket へ状態を書く。
// 読むのは Run だけが行い、書くのはこのロックの中だけである。
type wsLink struct {
	conn *websocket.Conn
	mu   sync.Mutex
}

func (l *wsLink) Send(ctx context.Context, msg protocol.PhoneMessage) error {
	body, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.conn.Write(ctx, websocket.MessageText, body)
}

// Run は、バックエンドと WebSocket でつながり続け、電話の指示が来るたびに電話をする。
// 接続が切れても、間隔を空けてつなぎ直す。ctx が終わると戻る。
// WatchedPerson が空なら、つなぐ前にエラーを返す。
func (d *Device) Run(ctx context.Context) error {
	if strings.TrimSpace(d.WatchedPerson) == "" {
		return errors.New("見守る方の ID が要ります。--watched-person で渡してください")
	}
	delay := reconnectMin
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		connected, err := d.serve(ctx)
		if ctx.Err() != nil {
			return ctx.Err()
		}
		// 一度でもつながったあとは、間隔を最初に戻す。つながらないあいだだけ伸ばす。
		if connected {
			delay = reconnectMin
		}
		log.Printf("バックエンドとの接続が切れたので、%s 後につなぎ直します: %v", delay, err)
		timer := d.Clock.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-timer.Chan():
		}
		if !connected {
			delay *= 2
			if delay > reconnectMax {
				delay = reconnectMax
			}
		}
	}
}

// StopCall は、今の電話だけを止める。バックエンドとの接続は切らない。
// 電話がまだ始まっていなければ、次に読む指示を始めない。
func (d *Device) StopCall() {
	d.mu.Lock()
	d.stopping = true
	cancel := d.cancelCall
	d.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

// armCall は、この指示の電話を始められるとき、その context を返す。
// StopCall のあとなら、始められると false を返す。
func (d *Device) armCall(parent context.Context) (context.Context, context.CancelFunc, bool) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.stopping {
		d.stopping = false
		return nil, nil, false
	}
	ctx, cancel := context.WithCancel(parent)
	d.cancelCall = cancel
	return ctx, cancel, true
}

func (d *Device) disarmCall() {
	d.mu.Lock()
	d.cancelCall = nil
	// 電話が終わったので、次の指示は止めたままにしない。
	d.stopping = false
	d.mu.Unlock()
}

func (d *Device) finish(err error) {
	if d.AfterCall != nil {
		d.AfterCall(err)
	}
}

// serve は、1 本の接続で指示を待ち、切れるまで電話をする。
// 接続できたら connected を true にする。ダイヤルに失敗したときは false である。
func (d *Device) serve(ctx context.Context) (connected bool, err error) {
	wsURL, err := phoneWebSocketURL(d.Backend, d.WatchedPerson)
	if err != nil {
		return false, err
	}
	conn, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		return false, err
	}
	defer conn.Close(websocket.StatusNormalClosure, "")
	link := &wsLink{conn: conn}
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return true, err
		}
		var msg protocol.PhoneMessage
		if json.Unmarshal(data, &msg) != nil || msg.Type != protocol.PhoneTypeCall || msg.CallID == "" {
			continue
		}
		callCtx, cancel, ok := d.armCall(ctx)
		if !ok {
			d.sendState(link, msg.CallID, protocol.StateFailed)
			d.finish(context.Canceled)
			continue
		}
		err = d.place(callCtx, link, msg.CallID)
		d.disarmCall()
		cancel()
		d.finish(err)
		if ctx.Err() != nil {
			return true, ctx.Err()
		}
		// 出なかった電話と、テストが止めた電話は、次の指示を待ち続ける。
		if err != nil && !errors.Is(err, errNoAnswer) && !errors.Is(err, context.Canceled) {
			log.Printf("電話が失敗しました: %v", err)
		}
	}
}

func phoneWebSocketURL(backend, personID string) (string, error) {
	u, err := url.Parse(backend)
	if err != nil {
		return "", err
	}
	switch u.Scheme {
	case "http":
		u.Scheme = "ws"
	case "https":
		u.Scheme = "wss"
	default:
		return "", fmt.Errorf("バックエンドの URL の scheme が %s だった", u.Scheme)
	}
	u.Path = protocol.PhonePath
	u.RawQuery = url.Values{"watchedPerson": {personID}}.Encode()
	return u.String(), nil
}
