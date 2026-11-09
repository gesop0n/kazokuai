package server

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// errPhoneNotConnected は、見守る方の電話機が今つながっていないときである。
var errPhoneNotConnected = errors.New("電話機がつながっていない")

// phoneBook は、つながっている電話機を見守る方の ID ごとにメモリーで持つ。
// プロセスが終わると消える。Cloud Run のインスタンスをまたぐ送り方は、ここに載せない。
type phoneBook struct {
	mu   sync.Mutex
	byID map[string]*phoneLink
}

func newPhoneBook() *phoneBook {
	return &phoneBook{byID: map[string]*phoneLink{}}
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

// add は、personID の電話機を link に付け替える。前の接続があれば閉じ、途中の電話の ID を返す。
func (b *phoneBook) add(personID string, link *phoneLink) (droppedCall string) {
	b.mu.Lock()
	old := b.byID[personID]
	if old != nil {
		old.mu.Lock()
		droppedCall = old.callID
		old.callID = ""
		old.mu.Unlock()
	}
	b.byID[personID] = link
	b.mu.Unlock()
	if old != nil {
		old.conn.Close(websocket.StatusGoingAway, "新しい接続に代わりました")
	}
	return droppedCall
}

// remove は、personID の接続が link のままなら外し、途中の電話の ID を返す。
// すでに別の接続に代わっていれば、何もしない。
func (b *phoneBook) remove(personID string, link *phoneLink) string {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.byID[personID] != link {
		return ""
	}
	delete(b.byID, personID)
	link.mu.Lock()
	defer link.mu.Unlock()
	callID := link.callID
	link.callID = ""
	return callID
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
	if dropped := s.phones.add(personID, link); dropped != "" {
		s.failCall(personID, dropped)
	}
	defer func() {
		if callID := s.phones.remove(personID, link); callID != "" {
			s.failCall(personID, callID)
		}
	}()

	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return
		}
		var msg protocol.PhoneMessage
		if json.Unmarshal(data, &msg) != nil || msg.Type != protocol.PhoneTypeState {
			continue
		}
		s.applyState(personID, msg.CallID, msg.State)
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
	_, err := s.callRef(personID, callID).Update(ctx, []firestore.Update{{Path: "state", Value: state}})
	if err != nil {
		log.Printf("電話 %s の状態を %s にできなかった: %v", callID, state, err)
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
