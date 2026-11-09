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

// errLinkDown は、状態を送るときに WebSocket がつながっていないときである。
// その状態は覚えておき、次につながったときに送る。
var errLinkDown = errors.New("バックエンドとつながっていない")

// callLink は、電話のあいだに状態を送る口である。WebSocket の接続を、電話の処理から隠す。
type callLink interface {
	Send(ctx context.Context, msg protocol.PhoneMessage) error
}

// sessionLink は、つなぎ直しても同じ口で状態を送る。
// 届かなかった状態は、次の接続で、古いものから送る。
// 読むのは Run だけが行い、書くのは writeMu の中だけである。
type sessionLink struct {
	mu      sync.Mutex
	writeMu sync.Mutex
	conn    *websocket.Conn
	pending []protocol.PhoneMessage
	// hasSent は、今の接続へ最後に書けた状態があるときである。
	// 接続が切れると、相手が読む前だったかもしれないので、もう一度送る。
	hasSent  bool
	lastSent protocol.PhoneMessage
}

func (l *sessionLink) Send(ctx context.Context, msg protocol.PhoneMessage) error {
	body, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	l.writeMu.Lock()
	defer l.writeMu.Unlock()
	l.mu.Lock()
	conn := l.conn
	if conn == nil {
		l.enqueue(msg)
		l.mu.Unlock()
		return errLinkDown
	}
	l.mu.Unlock()
	err = conn.Write(ctx, websocket.MessageText, body)
	l.mu.Lock()
	defer l.mu.Unlock()
	if err != nil || l.conn != conn {
		if l.conn == conn {
			l.conn = nil
		}
		l.enqueue(msg)
		if err == nil {
			err = errLinkDown
		}
		return err
	}
	l.lastSent = msg
	l.hasSent = true
	return nil
}

// enqueue は、msg を未達の列の末尾に足す。今の接続へ書けた状態があれば、その前に戻す。
// mu を持っているときに呼ぶ。
func (l *sessionLink) enqueue(msg protocol.PhoneMessage) {
	if l.hasSent {
		l.pending = append([]protocol.PhoneMessage{l.lastSent}, l.pending...)
		l.hasSent = false
	}
	l.pending = append(l.pending, msg)
}

// attach は、conn をこれからの書き込み先にし、未達の状態を順に送る。
func (l *sessionLink) attach(conn *websocket.Conn) error {
	l.writeMu.Lock()
	defer l.writeMu.Unlock()
	l.mu.Lock()
	batch := l.pending
	l.pending = nil
	l.conn = conn
	l.mu.Unlock()
	for i, msg := range batch {
		if err := writeState(conn, msg); err != nil {
			l.mu.Lock()
			l.pending = append(append([]protocol.PhoneMessage{}, batch[i:]...), l.pending...)
			l.mu.Unlock()
			return err
		}
		l.mu.Lock()
		l.lastSent = msg
		l.hasSent = true
		l.mu.Unlock()
	}
	return nil
}

// detach は、conn が今の接続なら外し、最後に書けた状態を未達に戻す。
func (l *sessionLink) detach(conn *websocket.Conn) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.conn != conn {
		return
	}
	l.conn = nil
	if l.hasSent {
		l.pending = append([]protocol.PhoneMessage{l.lastSent}, l.pending...)
		l.hasSent = false
	}
}

func writeState(conn *websocket.Conn, msg protocol.PhoneMessage) error {
	body, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), stateTimeout)
	defer cancel()
	return conn.Write(ctx, websocket.MessageText, body)
}

// callQueue は、電話の指示を、読む側を止めずに貯める。
// 通話中も接続の切断を読めるようにするため、入れた側は待たない。
type callQueue struct {
	mu   sync.Mutex
	ids  []string
	wake chan struct{}
}

func newCallQueue() *callQueue {
	return &callQueue{wake: make(chan struct{}, 1)}
}

func (q *callQueue) push(id string) {
	q.mu.Lock()
	q.ids = append(q.ids, id)
	q.mu.Unlock()
	select {
	case q.wake <- struct{}{}:
	default:
	}
}

func (q *callQueue) next(ctx context.Context) (string, bool) {
	for {
		q.mu.Lock()
		if len(q.ids) > 0 {
			id := q.ids[0]
			q.ids[0] = ""
			q.ids = q.ids[1:]
			q.mu.Unlock()
			return id, true
		}
		q.mu.Unlock()
		select {
		case <-ctx.Done():
			return "", false
		case <-q.wake:
		}
	}
}

// Run は、バックエンドと WebSocket でつながり続け、電話の指示が来るたびに電話をする。
// 電話のあいだも接続を読み、切れれば間隔を空けてつなぎ直す。届かなかった状態は、つなぎ直したあとに送る。
// ctx が終わると戻る。WatchedPerson が空なら、つなぐ前にエラーを返す。
func (d *Device) Run(ctx context.Context) error {
	if strings.TrimSpace(d.WatchedPerson) == "" {
		return errors.New("見守る方の ID が要ります。--watched-person で渡してください")
	}
	link := &sessionLink{}
	commands := newCallQueue()
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		d.handleCommands(ctx, link, commands)
	}()
	delay := reconnectMin
	for {
		if err := ctx.Err(); err != nil {
			wg.Wait()
			return err
		}
		connected, err := d.readOnce(ctx, link, commands)
		if ctx.Err() != nil {
			wg.Wait()
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
			wg.Wait()
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

// handleCommands は、指示が来るたびに 1 本ずつ電話をする。
func (d *Device) handleCommands(ctx context.Context, link callLink, commands *callQueue) {
	for {
		callID, ok := commands.next(ctx)
		if !ok {
			return
		}
		callCtx, cancel, armed := d.armCall(ctx)
		if !armed {
			d.sendState(link, callID, protocol.StateFailed)
			d.finish(context.Canceled)
			continue
		}
		err := d.place(callCtx, link, callID)
		d.disarmCall()
		cancel()
		d.finish(err)
		if ctx.Err() != nil {
			return
		}
		// 出なかった電話と、テストが止めた電話は、次の指示を待ち続ける。
		if err != nil && !errors.Is(err, errNoAnswer) && !errors.Is(err, context.Canceled) {
			log.Printf("電話が失敗しました: %v", err)
		}
	}
}

// readOnce は、1 本の接続で指示を読む。電話の処理は止めない。
// 接続できたら connected を true にする。ダイヤルに失敗したときは false である。
func (d *Device) readOnce(ctx context.Context, link *sessionLink, commands *callQueue) (bool, error) {
	wsURL, err := phoneWebSocketURL(d.Backend, d.WatchedPerson)
	if err != nil {
		return false, err
	}
	conn, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		return false, err
	}
	defer conn.Close(websocket.StatusNormalClosure, "")
	if err := link.attach(conn); err != nil {
		link.detach(conn)
		return true, err
	}
	defer link.detach(conn)
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return true, err
		}
		var msg protocol.PhoneMessage
		if json.Unmarshal(data, &msg) != nil || msg.Type != protocol.PhoneTypeCall || msg.CallID == "" {
			continue
		}
		commands.push(msg.CallID)
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
