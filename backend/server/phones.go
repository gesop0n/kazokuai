package server

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/internal/clock"
	"github.com/gesop0n/kazokuai/internal/keepalive"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// errPhoneNotConnected は、見守る方の電話機が今つながっていないときである。
var errPhoneNotConnected = errors.New("電話機がつながっていない")

// phoneBook は、つながっている電話機を見守る方の ID ごとにメモリーで持つ。
// プロセスが終わると消える。Cloud Run のインスタンスをまたぐ送り方は、ここに載せない。
type phoneBook struct {
	mu    sync.Mutex
	byID  map[string]*phoneLink
	grace map[string]*callGrace
}

// callGrace は、切れた接続の電話を、つなぎ直すまで待っているものである。
type callGrace struct {
	callID string
	cancel context.CancelFunc
}

func newPhoneBook() *phoneBook {
	return &phoneBook{
		byID:  map[string]*phoneLink{},
		grace: map[string]*callGrace{},
	}
}

// phoneLink は、1 台の電話機との WebSocket である。
type phoneLink struct {
	conn *websocket.Conn
	ctx  context.Context

	mu     sync.Mutex
	callID string
}

func (b *phoneBook) connected(personID string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	_, ok := b.byID[personID]
	return ok
}

// replace は、personID の接続を link にする。
// 猶予で待っていた電話と、前の接続が持っていた電話を link に引き継ぐ。
// 前の接続は、呼び出し側が閉じる。
func (b *phoneBook) replace(personID string, link *phoneLink) (old *phoneLink) {
	b.mu.Lock()
	defer b.mu.Unlock()
	var adopt string
	if g := b.grace[personID]; g != nil {
		delete(b.grace, personID)
		adopt = g.callID
		g.cancel()
	}
	old = b.byID[personID]
	if old != nil {
		old.mu.Lock()
		if adopt == "" {
			adopt = old.callID
		}
		old.callID = ""
		old.mu.Unlock()
	}
	link.mu.Lock()
	if link.callID == "" {
		link.callID = adopt
	}
	link.mu.Unlock()
	b.byID[personID] = link
	return old
}

// takeGrace は、g が personID の今の猶予なら外して true を返す。
func (b *phoneBook) takeGrace(personID string, g *callGrace) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.grace[personID] != g {
		return false
	}
	delete(b.grace, personID)
	return true
}

func (b *phoneBook) setCall(personID, callID string) {
	b.mu.Lock()
	link := b.byID[personID]
	b.mu.Unlock()
	if link == nil {
		return
	}
	link.mu.Lock()
	link.callID = callID
	link.mu.Unlock()
}

func (b *phoneBook) clearCall(personID, callID string) {
	b.mu.Lock()
	link := b.byID[personID]
	b.mu.Unlock()
	if link == nil {
		return
	}
	link.mu.Lock()
	defer link.mu.Unlock()
	if link.callID == callID {
		link.callID = ""
	}
}

// send は、personID の電話機に指示を送る。つながっていなければ errPhoneNotConnected を返す。
func (b *phoneBook) send(personID string, msg protocol.PhoneMessage) error {
	b.mu.Lock()
	link := b.byID[personID]
	b.mu.Unlock()
	if link == nil {
		return errPhoneNotConnected
	}
	body, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	link.mu.Lock()
	defer link.mu.Unlock()
	ctx, cancel := context.WithTimeout(link.ctx, 5*time.Second)
	defer cancel()
	if err := link.conn.Write(ctx, websocket.MessageText, body); err != nil {
		return err
	}
	// すでに追跡している電話があるときは、その ID を残す。
	// あとから来た指示で置き換えると、接続が切れたときに、今の電話を「つながらなかった」にできない。
	if link.callID == "" {
		link.callID = msg.CallID
	}
	return nil
}

// phone は、電話機からの WebSocket を受け、切れるまで状態を読む。
func (s *server) phone(w http.ResponseWriter, r *http.Request) {
	personID := r.URL.Query().Get("watchedPerson")
	if personID == "" {
		http.Error(w, "見守る方の ID を watchedPerson で指定してください", http.StatusBadRequest)
		return
	}
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		log.Printf("電話機の接続を受けられなかった: %v", err)
		return
	}
	defer conn.Close(websocket.StatusNormalClosure, "")

	ctx, cancel := context.WithCancel(s.base)
	defer cancel()
	go func() {
		select {
		case <-s.base.Done():
			conn.Close(websocket.StatusGoingAway, "バックエンドが止まった")
			cancel()
		case <-ctx.Done():
		}
	}()

	link := &phoneLink{conn: conn, ctx: ctx}
	if old := s.phones.replace(personID, link); old != nil {
		old.conn.Close(websocket.StatusGoingAway, "新しい接続に代わりました")
	}
	s.logf("電話機がつながりました。見守る方: %s", personID)
	defer s.disconnect(personID, link)
	go keepalive.Run(ctx, s.clock, conn)

	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			s.logf("電話機が切れました。見守る方: %s、理由: %s", personID, s.dropReason(err))
			return
		}
		var msg protocol.PhoneMessage
		if json.Unmarshal(data, &msg) != nil || msg.Type != protocol.PhoneTypeState {
			continue
		}
		s.applyState(personID, msg.CallID, msg.State)
	}
}

// logf は、電話機のつながりを書く。Logger があればそこへ、無ければ標準のログへ書く。
func (s *server) logf(format string, args ...any) {
	if s.config.Logger != nil {
		s.config.Logger.Printf(format, args...)
		return
	}
	log.Printf(format, args...)
}

// dropReason は、切れた接続の理由である。合言葉は出さない。
func (s *server) dropReason(err error) string {
	if s.base.Err() != nil {
		return "バックエンドが止まった"
	}
	var closed websocket.CloseError
	if errors.As(err, &closed) && closed.Reason != "" {
		return s.redact(closed.Reason)
	}
	if errors.As(err, &closed) && closed.Code == websocket.StatusNormalClosure {
		return "電話機が閉じた"
	}
	if err == nil {
		return "接続が切れた"
	}
	return s.redact(err.Error())
}

func (s *server) redact(text string) string {
	secret := s.config.PhoneSecret
	if secret == "" {
		return text
	}
	return strings.ReplaceAll(text, secret, "[合言葉]")
}

// disconnect は、personID の接続が link のままなら外す。
// 途中の電話があれば、つなぎ直すまでの猶予を始めてから戻る。
func (s *server) disconnect(personID string, link *phoneLink) {
	s.phones.mu.Lock()
	defer s.phones.mu.Unlock()
	if s.phones.byID[personID] != link {
		return
	}
	delete(s.phones.byID, personID)
	link.mu.Lock()
	callID := link.callID
	link.callID = ""
	link.mu.Unlock()
	if callID == "" || s.base.Err() != nil {
		return
	}
	s.armGraceLocked(personID, callID)
}

// armGraceLocked は、電話機の本のロックを持っているときに呼ぶ。
// タイマーを登録してから戻るので、接続が外れたと見えたときには、猶予が始まっている。
func (s *server) armGraceLocked(personID, callID string) {
	ctx, cancel := context.WithCancel(s.base)
	g := &callGrace{callID: callID, cancel: cancel}
	if old := s.phones.grace[personID]; old != nil {
		old.cancel()
	}
	s.phones.grace[personID] = g
	timer := s.newTimer(protocol.ReconnectGrace)
	go s.runGrace(ctx, timer, personID, g)
}

func (s *server) runGrace(ctx context.Context, timer clock.Timer, personID string, g *callGrace) {
	select {
	case <-ctx.Done():
		timer.Stop()
	case <-timer.Chan():
		if ctx.Err() != nil {
			return
		}
		if s.phones.takeGrace(personID, g) {
			s.failCall(personID, g.callID)
		}
	}
}

func (s *server) applyState(personID, callID, state string) {
	switch state {
	case protocol.StateRinging, protocol.StateTalking, protocol.StateEnded, protocol.StateMissed, protocol.StateFailed:
	default:
		return
	}
	if callID == "" {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	ref := s.callRef(personID, callID)
	// トランザクションがやり直されても、最後に書けたときだけ追跡を変える。
	applied := false
	err := s.firebase.Firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		applied = false
		doc, err := tx.Get(ref)
		if err != nil {
			return err
		}
		current, _ := doc.Data()["state"].(string)
		// 電話機は、切れる前の呼び出し中や通話中を、つなぎ直したときに送り直す。
		// 猶予を過ぎてつながらなかった電話を、その古い状態で進行中に戻さない。
		if current == protocol.StateFailed && (state == protocol.StateRinging || state == protocol.StateTalking) {
			return nil
		}
		if err := tx.Update(ref, []firestore.Update{{Path: "state", Value: state}}); err != nil {
			return err
		}
		applied = true
		return nil
	})
	if err != nil {
		log.Printf("電話 %s の状態を %s にできなかった: %v", callID, state, err)
		return
	}
	if !applied {
		return
	}
	switch state {
	case protocol.StateEnded, protocol.StateMissed, protocol.StateFailed:
		s.phones.clearCall(personID, callID)
	default:
		s.phones.setCall(personID, callID)
	}
}

// failCall は、呼び出し中か通話中の電話を、つながらなかったにする。
// すでに終わっている電話は変えない。読み取りと書き込みは 1 つのトランザクションなので、
// そのあいだに届いた終わりの状態を、つながらなかったで上書きしない。
func (s *server) failCall(personID, callID string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	ref := s.callRef(personID, callID)
	err := s.firebase.Firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		if err != nil {
			return err
		}
		state, _ := doc.Data()["state"].(string)
		if state != protocol.StateRinging && state != protocol.StateTalking {
			return nil
		}
		return tx.Update(ref, []firestore.Update{{Path: "state", Value: protocol.StateFailed}})
	})
	if err != nil {
		log.Printf("電話 %s を %s にできなかった: %v", callID, protocol.StateFailed, err)
	}
}

func (s *server) callRef(personID, callID string) *firestore.DocumentRef {
	return s.firebase.Firestore.Collection(watchedPersons).Doc(personID).Collection(callsCollection).Doc(callID)
}
