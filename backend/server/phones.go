package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode"

	"cloud.google.com/go/firestore"
	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/internal/clock"
	"github.com/gesop0n/kazokuai/internal/keepalive"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// errPhoneNotConnected は、見守る方の電話機が今つながっていないときである。
var errPhoneNotConnected = errors.New("電話機がつながっていない")

// phoneBook は、つながっている電話機をメモリーで持つ。
// 古い道の電話機は見守る方の ID ごと、ID と鍵で認証した電話機は電話機の ID ごとである。
// プロセスが終わると消える。Cloud Run のインスタンスをまたぐ送り方は、ここに載せない。
type phoneBook struct {
	mu      sync.Mutex
	byID    map[string]*phoneLink
	byPhone map[string]*phoneLink
	grace   map[string]*callGrace
}

// callGrace は、切れた接続の電話を、つなぎ直すまで待っているものである。
type callGrace struct {
	callID string
	cancel context.CancelFunc
}

func newPhoneBook() *phoneBook {
	return &phoneBook{
		byID:    map[string]*phoneLink{},
		byPhone: map[string]*phoneLink{},
		grace:   map[string]*callGrace{},
	}
}

// phoneLink は、1 台の電話機との WebSocket である。
type phoneLink struct {
	conn *websocket.Conn
	ctx  context.Context

	mu       sync.Mutex
	personID string
	callID   string
}

func (b *phoneBook) connected(personID string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	_, ok := b.byID[personID]
	return ok
}

func (b *phoneBook) hasPhone(phoneID string) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	_, ok := b.byPhone[phoneID]
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

// sendPhone は、phoneID の電話機に指示を送る。つながっていなければ errPhoneNotConnected を返す。
// 届いた指示の見守る方を、その接続が今の電話の相手として覚える。
func (b *phoneBook) sendPhone(phoneID, personID string, msg protocol.PhoneMessage) error {
	b.mu.Lock()
	link := b.byPhone[phoneID]
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
	link.personID = personID
	if link.callID == "" {
		link.callID = msg.CallID
	}
	return nil
}

// notify は、phoneID の電話機に知らせを送る。電話の追跡は変えない。
func (b *phoneBook) notify(phoneID string, msg protocol.PhoneMessage) error {
	b.mu.Lock()
	link := b.byPhone[phoneID]
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
	return link.conn.Write(ctx, websocket.MessageText, body)
}

// detachPerson は、phoneID の接続が覚えていた見守る方と電話を外す。
// 同期していない電話機に戻したあとに届く状態で、終えた電話を上書きしない。
func (b *phoneBook) detachPerson(phoneID string) {
	b.mu.Lock()
	link := b.byPhone[phoneID]
	b.mu.Unlock()
	if link == nil {
		return
	}
	link.mu.Lock()
	link.personID = ""
	link.callID = ""
	link.mu.Unlock()
}

// phone は、電話機からの WebSocket を受け、切れるまで状態を読む。
// ID と鍵で認証した電話機は、電話機の ID ごとに持つ。古い道は、名乗った見守る方ごとに持つ。
func (s *server) phone(w http.ResponseWriter, r *http.Request) {
	if identity := phoneIdentityFrom(r.Context()); identity.phoneID != "" {
		s.phoneWithKey(w, r, identity)
		return
	}
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
		s.applyState(personID, msg.CallID, msg.State, nil)
	}
}

// phoneWithKey は、ID と鍵で認証した電話機の WebSocket を受け、切れるまで状態を読む。
// 同期していない電話機も、つながったままにする。電話は、結び付きがあるときだけ届く。
func (s *server) phoneWithKey(w http.ResponseWriter, r *http.Request, identity phoneIdentity) {
	named := r.URL.Query().Get("watchedPerson")
	if named != "" && named != identity.personID {
		http.Error(w, protocol.PhoneAnswerOtherPerson, http.StatusForbidden)
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
	if old := s.phones.replacePhone(identity.phoneID, identity.personID, link); old != nil {
		old.conn.Close(websocket.StatusGoingAway, "新しい接続に代わりました")
	}
	s.logf("電話機がつながりました。見守る方: %s", identity.personID)
	// つながっていなかった電話機は、つないだときに自分の状態を知る。
	s.tellSyncState(identity.phoneID, identity.personID != "")
	defer s.disconnectPhone(identity.phoneID, link)
	go keepalive.Run(ctx, s.clock, conn)

	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			link.mu.Lock()
			personID := link.personID
			link.mu.Unlock()
			s.logf("電話機が切れました。見守る方: %s、理由: %s", personID, s.dropReason(err))
			return
		}
		var msg protocol.PhoneMessage
		if json.Unmarshal(data, &msg) != nil || msg.Type != protocol.PhoneTypeState {
			continue
		}
		link.mu.Lock()
		personID := link.personID
		link.mu.Unlock()
		if personID == "" {
			continue
		}
		s.applyState(personID, msg.CallID, msg.State, link)
	}
}

// replacePhone は、phoneID の接続を link にする。
// personID の猶予で待っていた電話と、前の接続が持っていた電話を link に引き継ぐ。
func (b *phoneBook) replacePhone(phoneID, personID string, link *phoneLink) (old *phoneLink) {
	b.mu.Lock()
	defer b.mu.Unlock()
	var adopt string
	if personID != "" {
		if g := b.grace[personID]; g != nil {
			delete(b.grace, personID)
			adopt = g.callID
			g.cancel()
		}
	}
	old = b.byPhone[phoneID]
	if old != nil {
		old.mu.Lock()
		if adopt == "" {
			adopt = old.callID
		}
		old.callID = ""
		old.mu.Unlock()
	}
	link.mu.Lock()
	link.personID = personID
	if link.callID == "" {
		link.callID = adopt
	}
	link.mu.Unlock()
	b.byPhone[phoneID] = link
	return old
}

// disconnectPhone は、phoneID の接続が link のままなら外す。
// 途中の電話があれば、その見守る方について、つなぎ直すまでの猶予を始める。
func (s *server) disconnectPhone(phoneID string, link *phoneLink) {
	s.phones.mu.Lock()
	defer s.phones.mu.Unlock()
	if s.phones.byPhone[phoneID] != link {
		return
	}
	delete(s.phones.byPhone, phoneID)
	link.mu.Lock()
	callID := link.callID
	personID := link.personID
	link.callID = ""
	link.mu.Unlock()
	if callID == "" || personID == "" || s.base.Err() != nil {
		return
	}
	s.armGraceLocked(personID, callID)
}

func (l *phoneLink) rememberCall(callID string) {
	l.mu.Lock()
	l.callID = callID
	l.mu.Unlock()
}

func (l *phoneLink) forgetCall(callID string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.callID == callID {
		l.callID = ""
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

// dropReason は、切れた接続の理由である。合言葉は出さず、改行も 1 行に収める。
func (s *server) dropReason(err error) string {
	reason := "接続が切れた"
	if s.base.Err() != nil {
		reason = "バックエンドが止まった"
	} else if err != nil {
		var closed websocket.CloseError
		switch {
		case errors.As(err, &closed) && closed.Reason != "":
			reason = closed.Reason
		case errors.As(err, &closed) && closed.Code == websocket.StatusNormalClosure:
			reason = "電話機が閉じた"
		default:
			reason = err.Error()
		}
	}
	return oneLine(s.redact(reason))
}

// oneLine は、改行と制御文字を見える形に変えて、ログが 1 行のままになるようにする。
func oneLine(text string) string {
	var b strings.Builder
	b.Grow(len(text))
	for _, r := range text {
		switch r {
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		default:
			if unicode.IsControl(r) {
				fmt.Fprintf(&b, `\u%04x`, r)
			} else {
				b.WriteRune(r)
			}
		}
	}
	return b.String()
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

func (s *server) applyState(personID, callID, state string, link *phoneLink) {
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
	if link != nil {
		switch state {
		case protocol.StateEnded, protocol.StateMissed, protocol.StateFailed:
			link.forgetCall(callID)
		default:
			link.rememberCall(callID)
		}
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
