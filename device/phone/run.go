package phone

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"sync"
	"time"

	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/internal/keepalive"
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

// queuedCall は、まだ始めていない 1 本の電話である。
type queuedCall struct {
	id          string
	fromHandset bool
}

// callQueue は、電話の指示を、読む側を止めずに貯める。
// 通話中も接続の切断を読めるようにするため、入れた側は待たない。
type callQueue struct {
	mu    sync.Mutex
	items []queuedCall
	wake  chan struct{}
}

func newCallQueue() *callQueue {
	return &callQueue{wake: make(chan struct{}, 1)}
}

func (q *callQueue) push(id string) {
	q.enqueue(queuedCall{id: id})
}

// pushOwn は、電話機が始めた電話を貯める。受話器は上がっているので、鳴らさない。
func (q *callQueue) pushOwn(id string) {
	q.enqueue(queuedCall{id: id, fromHandset: true})
}

func (q *callQueue) enqueue(item queuedCall) {
	q.mu.Lock()
	q.items = append(q.items, item)
	q.mu.Unlock()
	select {
	case q.wake <- struct{}{}:
	default:
	}
}

// try は、待っている電話が 1 本あればそれを返す。無ければ false で、待たない。
func (q *callQueue) try() (queuedCall, bool) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if len(q.items) == 0 {
		return queuedCall{}, false
	}
	item := q.items[0]
	q.items[0] = queuedCall{}
	q.items = q.items[1:]
	return item, true
}

// Run は、バックエンドと WebSocket でつながり続け、電話の指示が来るたびに電話をする。
// 電話のあいだも接続を読み、切れれば間隔を空けてつなぎ直す。届かなかった状態は、つなぎ直したあとに送る。
// ctx が終わると戻る。ID と鍵が無ければ、つなぐ前にエラーを返す。
// 先に登録する。バックエンドがその ID を知らないときは、同じ ID と鍵で登録し直す。
func (d *Device) Run(ctx context.Context) error {
	if d.Identity.ID == "" || d.Identity.Key == "" {
		return errors.New("電話機の ID と鍵が要ります")
	}
	if err := d.Register(ctx); err != nil {
		return err
	}
	d.speeches = make(chan speech, 1)
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

// handleCommands は、電話が来るまでフックとキーパッドを見て、来たら 1 本ずつ電話をする。
func (d *Device) handleCommands(ctx context.Context, link callLink, commands *callQueue) {
	for {
		call, ok := d.idleUntilCall(ctx, commands)
		if !ok {
			return
		}
		d.setCalling(true)
		d.stopSpeaking()
		callCtx, cancel, armed := d.armCall(ctx)
		if !armed {
			d.setCalling(false)
			d.sendState(link, call.id, protocol.StateFailed)
			d.finish(context.Canceled)
			continue
		}
		err := d.place(callCtx, link, call.id, call.fromHandset)
		d.disarmCall()
		cancel()
		// 呼び出し中に置いても、出なかった電話はそこで終わらない。戻ったときに、今の受話器を読み直す。
		d.adoptHandset()
		d.setCalling(false)
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
	wsURL, err := phoneWebSocketURL(d.Backend)
	if err != nil {
		return false, err
	}
	conn, err := d.dialPhone(ctx, wsURL)
	if err != nil {
		return false, err
	}
	defer conn.Close(websocket.StatusNormalClosure, "")
	if err := link.attach(conn); err != nil {
		link.detach(conn)
		return true, err
	}
	defer link.detach(conn)
	pingCtx, stopPing := context.WithCancel(ctx)
	defer stopPing()
	go keepalive.Run(pingCtx, d.Clock, conn)
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return true, err
		}
		var msg protocol.PhoneMessage
		if json.Unmarshal(data, &msg) != nil {
			continue
		}
		switch msg.Type {
		case protocol.PhoneTypeCall:
			if msg.CallID != "" {
				commands.push(msg.CallID)
			}
		case protocol.PhoneTypeSynced:
			// 受話器が上がっていて電話の最中でないときだけ、その場で完了を話す。あとには残さない。
			d.deliverSynced()
		}
	}
}

// dialPhone は、WebSocket をつなぐ。ID を知らないと返されたときは、同じ ID と鍵で登録してからもう一度つなぐ。
func (d *Device) dialPhone(ctx context.Context, wsURL string) (*websocket.Conn, error) {
	conn, resp, err := d.dial(ctx, wsURL)
	if err == nil {
		return conn, nil
	}
	if d.Identity.ID == "" {
		closeBody(resp)
		return nil, err
	}
	unknown, uerr := unknownPhone(resp)
	closeBody(resp)
	if uerr != nil {
		return nil, uerr
	}
	if !unknown {
		return nil, err
	}
	if err := d.Register(ctx); err != nil {
		return nil, err
	}
	conn, resp, err = d.dial(ctx, wsURL)
	closeBody(resp)
	return conn, err
}

func (d *Device) dial(ctx context.Context, wsURL string) (*websocket.Conn, *http.Response, error) {
	header := http.Header{}
	d.authorize(header)
	return websocket.Dial(ctx, wsURL, &websocket.DialOptions{
		HTTPHeader: header,
		HTTPClient: d.HTTP,
	})
}

func closeBody(resp *http.Response) {
	if resp != nil && resp.Body != nil {
		resp.Body.Close()
	}
}

func phoneWebSocketURL(backend string) (string, error) {
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
	u.RawQuery = ""
	return u.String(), nil
}
