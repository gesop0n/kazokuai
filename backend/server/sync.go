package server

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

const (
	// syncPrepTTL は、同期の準備が続く時間である。
	syncPrepTTL = 10 * time.Minute
	// syncCodeTTL は、認証コードが有効な時間である。
	syncCodeTTL = 10 * time.Minute
	// syncPrepWindow は、同期の準備の回数を数える時間である。
	syncPrepWindow = time.Hour
	// syncPrepLimit は、syncPrepWindow のあいだに 1 人の家族が始められる回数である。
	syncPrepLimit = 5
	// syncWrongLimit は、間違いで同期の準備が終わる回数である。
	syncWrongLimit = 5
)

// errPhoneTaken は、認証コードの電話機が、送った家族以外に結び付いていたときである。
// 先に届いた結び付けが勝つ。
var errPhoneTaken = errors.New("認証コードはもう使われた")

// syncBook は、同期の準備と認証コードと、その回数をメモリーに置く。
// 再起動すると消える。Cloud Run は 1 インスタンスなので、プロセスの外には出さない。
type syncBook struct {
	mu     sync.Mutex
	preps  map[string]*syncPrep
	codes  map[string]*syncCode
	byCode map[string]string
	starts map[string][]time.Time
}

// syncPrep は、1 人の家族の、今開いている同期の準備である。
type syncPrep struct {
	expiresAt time.Time
	wrong     int
}

// syncCode は、1 台の電話機に出している認証コードである。
type syncCode struct {
	phoneID   string
	code      string
	expiresAt time.Time
}

func newSyncBook() *syncBook {
	return &syncBook{
		preps:  map[string]*syncPrep{},
		codes:  map[string]*syncCode{},
		byCode: map[string]string{},
		starts: map[string][]time.Time{},
	}
}

// start は、uid の同期の準備を始める。
// すでに開いていれば、それを返し、回数には数えない。
// 1 時間に 5 回を超えると、limited が true で、新しいものは作らない。
func (b *syncBook) start(uid string, now time.Time) (expires time.Time, created, limited bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if prep := b.prep(uid, now); prep != nil {
		return prep.expiresAt, false, false
	}
	fresh := b.recentStarts(uid, now)
	if len(fresh) >= syncPrepLimit {
		b.starts[uid] = fresh
		return time.Time{}, false, true
	}
	expires = now.Add(syncPrepTTL)
	b.preps[uid] = &syncPrep{expiresAt: expires}
	b.starts[uid] = append(fresh, now)
	return expires, true, false
}

// prepOpen は、uid の同期の準備が今開いているかを返す。
func (b *syncBook) prepOpen(uid string, now time.Time) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.prep(uid, now) != nil
}

// anyOpen は、uids のどれかに開いている同期の準備があるかを返す。
func (b *syncBook) anyOpen(uids []string, now time.Time) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	for _, uid := range uids {
		if b.prep(uid, now) != nil {
			return true
		}
	}
	return false
}

// prep は、開いている同期の準備を返す。切れていれば消して nil を返す。ロックを持って呼ぶ。
func (b *syncBook) prep(uid string, now time.Time) *syncPrep {
	prep := b.preps[uid]
	if prep == nil {
		return nil
	}
	if !now.Before(prep.expiresAt) {
		delete(b.preps, uid)
		return nil
	}
	return prep
}

// recentStarts は、1 時間より前に始めた同期の準備を除いた時刻である。ロックを持って呼ぶ。
func (b *syncBook) recentStarts(uid string, now time.Time) []time.Time {
	var fresh []time.Time
	for _, at := range b.starts[uid] {
		if now.Sub(at) < syncPrepWindow {
			fresh = append(fresh, at)
		}
	}
	return fresh
}

// issue は、phoneID の認証コードを返す。有効なあいだは同じコードである。
// ほかの有効な認証コードとは重ならない。
func (b *syncBook) issue(phoneID string, now time.Time) (string, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if existing := b.codes[phoneID]; existing != nil && now.Before(existing.expiresAt) {
		return existing.code, nil
	}
	b.deleteCode(phoneID)
	for range 8 {
		code, err := randomCode()
		if err != nil {
			return "", err
		}
		if owner, ok := b.byCode[code]; ok {
			other := b.codes[owner]
			if other != nil && other.code == code && now.Before(other.expiresAt) {
				continue
			}
			b.deleteCode(owner)
		}
		b.codes[phoneID] = &syncCode{phoneID: phoneID, code: code, expiresAt: now.Add(syncCodeTTL)}
		b.byCode[code] = phoneID
		return code, nil
	}
	return "", errors.New("認証コードを作れなかった")
}

// lookup は、有効な認証コードを出した電話機の ID を返す。
func (b *syncBook) lookup(code string, now time.Time) (phoneID string, ok bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	phoneID, found := b.byCode[code]
	if !found {
		return "", false
	}
	item := b.codes[phoneID]
	if item == nil || item.code != code || !now.Before(item.expiresAt) {
		b.deleteCode(phoneID)
		return "", false
	}
	return phoneID, true
}

// dropCode は、phoneID の認証コードを捨てる。電話を始めたときと、結び付けたときに使う。
func (b *syncBook) dropCode(phoneID string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.deleteCode(phoneID)
}

// deleteCode は、phoneID の認証コードを消す。ロックを持って呼ぶ。
func (b *syncBook) deleteCode(phoneID string) {
	item := b.codes[phoneID]
	if item == nil {
		return
	}
	if b.byCode[item.code] == phoneID {
		delete(b.byCode, item.code)
	}
	delete(b.codes, phoneID)
}

// end は、uid の同期の準備を終える。
func (b *syncBook) end(uid string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	delete(b.preps, uid)
}

// markWrong は、開いている同期の準備の間違いを 1 つ増やす。
// 5 回目なら準備を終わらせて true を返す。準備がもう無いときも true である。
func (b *syncBook) markWrong(uid string, now time.Time) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	prep := b.prep(uid, now)
	if prep == nil {
		return true
	}
	prep.wrong++
	if prep.wrong >= syncWrongLimit {
		delete(b.preps, uid)
		return true
	}
	return false
}

func randomCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1_000_000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

type syncPrepBody struct {
	ExpiresAt time.Time `json:"expiresAt"`
}

type syncCodeBody struct {
	Code string `json:"code"`
}

type syncCodeRequest struct {
	Code string `json:"code"`
}

type syncLinkedBody struct {
	WatchedPersonID string `json:"watchedPersonId"`
}

// startSyncPrep は、家族の同期の準備を始める。
func (s *server) startSyncPrep(w http.ResponseWriter, r *http.Request) {
	uid, ok := s.familyUID(w, r)
	if !ok {
		return
	}
	expires, created, limited := s.syncs.start(uid, s.now())
	if limited {
		writeAPIError(w, http.StatusTooManyRequests, protocol.SyncPrepLimited)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	if created {
		w.WriteHeader(http.StatusCreated)
	}
	json.NewEncoder(w).Encode(syncPrepBody{ExpiresAt: expires})
}

// issueSyncCode は、ID と鍵で認証した電話機に認証コードを出す。
// 同期していない電話機はいつでももらえる。同期済みの電話機は、その見守る方の家族が同期の準備を始めているあいだだけもらえる。
func (s *server) issueSyncCode(w http.ResponseWriter, r *http.Request) {
	identity := phoneIdentityFrom(r.Context())
	if identity.legacy || identity.phoneID == "" {
		http.Error(w, "電話機の ID と鍵を入れてください", http.StatusBadRequest)
		return
	}
	allowed, err := s.phoneMayHaveCode(r.Context(), identity)
	if err != nil {
		log.Printf("認証コードを出せなかった: %v", err)
		http.Error(w, "認証コードを出せなかった", http.StatusInternalServerError)
		return
	}
	if !allowed {
		http.Error(w, protocol.PhoneAnswerSyncClosed, http.StatusConflict)
		return
	}
	code, err := s.syncs.issue(identity.phoneID, s.now())
	if err != nil {
		log.Printf("認証コードを作れなかった: %v", err)
		http.Error(w, "認証コードを出せなかった", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(syncCodeBody{Code: code})
}

// phoneMayHaveCode は、この電話機が今、認証コードをもらえるかを返す。
func (s *server) phoneMayHaveCode(ctx context.Context, identity phoneIdentity) (bool, error) {
	if identity.personID == "" {
		return true, nil
	}
	person, err := readWatchedPerson(ctx, s.firebase.Firestore, identity.personID)
	if err != nil {
		return false, err
	}
	return s.syncs.anyOpen(person.FamilyUIDs, s.now()), nil
}

// sendSyncCode は、家族が送った認証コードを受け付け、電話機を見守る方に結び付ける。
func (s *server) sendSyncCode(w http.ResponseWriter, r *http.Request) {
	uid, ok := s.familyUID(w, r)
	if !ok {
		return
	}
	var req syncCodeRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxRegistration)).Decode(&req); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return
	}
	code := strings.TrimSpace(req.Code)
	now := s.now()
	if !s.syncs.prepOpen(uid, now) {
		writeAPIError(w, http.StatusConflict, protocol.SyncPrepEnded)
		return
	}
	phoneID, valid := s.syncs.lookup(code, now)
	if !valid {
		s.answerWrongCode(w, uid, now)
		return
	}
	match, err := s.codeFamilyOK(r.Context(), uid, phoneID)
	if err != nil {
		log.Printf("認証コードを確かめられなかった: %v", err)
		http.Error(w, "認証コードを確かめられなかった", http.StatusInternalServerError)
		return
	}
	if !match {
		s.answerWrongCode(w, uid, now)
		return
	}
	result, err := s.linkPhone(r.Context(), uid, phoneID, now)
	if errors.Is(err, errPhoneTaken) {
		s.answerWrongCode(w, uid, now)
		return
	}
	if err != nil {
		log.Printf("電話機 %s を結び付けられなかった: %v", phoneID, err)
		http.Error(w, "電話機を結び付けられなかった", http.StatusInternalServerError)
		return
	}
	s.syncs.dropCode(phoneID)
	s.syncs.end(uid)
	if result.created {
		log.Printf("名前のない見守る方 %s を作り、電話機 %s を結び付けました", result.personID, phoneID)
	} else if !result.unchanged {
		log.Printf("電話機 %s を見守る方 %s に結び付けました", phoneID, result.personID)
	}
	s.tellLinked(phoneID, result)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(syncLinkedBody{WatchedPersonID: result.personID})
}

// answerWrongCode は、間違いを数え、5 回目なら同期の準備が終わったと返す。
func (s *server) answerWrongCode(w http.ResponseWriter, uid string, now time.Time) {
	if s.syncs.markWrong(uid, now) {
		writeAPIError(w, http.StatusConflict, protocol.SyncPrepEnded)
		return
	}
	writeAPIError(w, http.StatusBadRequest, protocol.SyncCodeWrong)
}

// codeFamilyOK は、認証コードの電話機を uid の家族が結び付けてよいかを返す。
// 同期していない電話機は、同期の準備を始めている家族ならだれでもよい。
// 同期済みの電話機は、その見守る方の家族だけである。
func (s *server) codeFamilyOK(ctx context.Context, uid, phoneID string) (bool, error) {
	doc, err := s.firebase.Firestore.Collection(phonesCollection).Doc(phoneID).Get(ctx)
	if err != nil {
		return false, err
	}
	var phone phoneRecord
	if err := doc.DataTo(&phone); err != nil {
		return false, err
	}
	if phone.WatchedPersonID == "" {
		return true, nil
	}
	person, err := readWatchedPerson(ctx, s.firebase.Firestore, phone.WatchedPersonID)
	if err != nil {
		return false, err
	}
	for _, family := range person.FamilyUIDs {
		if family == uid {
			return true, nil
		}
	}
	return false, nil
}

// linkResult は、電話機を見守る方に結び付けた結果である。
type linkResult struct {
	personID  string
	replaced  string
	unchanged bool
	created   bool
}

// linkPhone は、phoneID を uid の見守る方に、1 つのトランザクションで結び付ける。
// 見守る方がいなければ、名前と呼び方が空の見守る方を作る。
// 別の電話機が付いていれば、それを同期していない電話機に戻し、その電話を「つながらなかった」で終える。
// 同じ電話機なら、何も変えない。
func (s *server) linkPhone(ctx context.Context, uid, phoneID string, now time.Time) (linkResult, error) {
	store := s.firebase.Firestore
	phoneRef := store.Collection(phonesCollection).Doc(phoneID)
	people := store.Collection(watchedPersons)
	newRef := people.NewDoc()
	var result linkResult
	err := store.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		result = linkResult{}
		phoneSnap, err := tx.Get(phoneRef)
		if err != nil {
			return err
		}
		var phone phoneRecord
		if err := phoneSnap.DataTo(&phone); err != nil {
			return err
		}
		existing, err := tx.Documents(people.Where("familyUids", "array-contains", uid).Limit(1)).GetAll()
		if err != nil {
			return err
		}
		var personRef *firestore.DocumentRef
		var person watchedPerson
		created := len(existing) == 0
		if created {
			personRef = newRef
		} else {
			personRef = existing[0].Ref
			if err := existing[0].DataTo(&person); err != nil {
				return err
			}
		}
		// ほかの家族の結び付けが先に届いている。読み直したトランザクションでは、ここに入る。
		if phone.WatchedPersonID != "" && (created || phone.WatchedPersonID != personRef.ID) {
			return errPhoneTaken
		}
		if !created && person.PhoneID == phoneID {
			result.personID = personRef.ID
			result.unchanged = true
			return nil
		}

		var oldRef *firestore.DocumentRef
		if !created && person.PhoneID != "" && person.PhoneID != phoneID {
			result.replaced = person.PhoneID
			ref := store.Collection(phonesCollection).Doc(person.PhoneID)
			_, err := tx.Get(ref)
			switch {
			case status.Code(err) == codes.NotFound:
			case err != nil:
				return err
			default:
				oldRef = ref
			}
		}
		var busy []*firestore.DocumentSnapshot
		if result.replaced != "" {
			busy, err = tx.Documents(personRef.Collection(callsCollection).Where("state", "in", []string{protocol.StateRinging, protocol.StateTalking})).GetAll()
			if err != nil {
				return err
			}
		}

		if created {
			if err := tx.Create(personRef, map[string]any{
				"name":       "",
				"callName":   "",
				"familyUids": []string{uid},
				"phoneId":    phoneID,
				"syncedAt":   now,
			}); err != nil {
				return err
			}
			result.created = true
		} else if err := tx.Update(personRef, []firestore.Update{
			{Path: "phoneId", Value: phoneID},
			{Path: "syncedAt", Value: now},
		}); err != nil {
			return err
		}
		if err := tx.Update(phoneRef, []firestore.Update{
			{Path: "watchedPersonId", Value: personRef.ID},
			{Path: "syncedAt", Value: now},
		}); err != nil {
			return err
		}
		if oldRef != nil {
			if err := tx.Update(oldRef, []firestore.Update{
				{Path: "watchedPersonId", Value: ""},
			}); err != nil {
				return err
			}
		}
		for _, doc := range busy {
			if err := tx.Update(doc.Ref, []firestore.Update{{Path: "state", Value: protocol.StateFailed}}); err != nil {
				return err
			}
		}
		result.personID = personRef.ID
		return nil
	})
	if err != nil {
		return linkResult{}, err
	}
	return result, nil
}

// tellLinked は、結び付きが変わった電話機に WebSocket で知らせる。
// 同じ電話機のときは知らせない。受話器が、同期の完了を重ねて話さないようにするためである。
// 同期していない電話機に戻った電話機は、メモリー上の見守る方を外す。あとから届く状態で、終えた電話を上書きしない。
func (s *server) tellLinked(phoneID string, result linkResult) {
	if result.replaced != "" {
		s.phones.detachPerson(result.replaced)
		s.tellSyncState(result.replaced, false)
		log.Printf("電話機 %s を同期していない電話機に戻しました", result.replaced)
	}
	if !result.unchanged {
		s.tellSyncState(phoneID, true)
	}
}

// tellSyncState は、つながっている電話機に、同期済みか、同期していないかを知らせる。
func (s *server) tellSyncState(phoneID string, synced bool) {
	kind := protocol.PhoneTypeNotSynced
	if synced {
		kind = protocol.PhoneTypeSynced
	}
	if err := s.phones.notify(phoneID, protocol.PhoneMessage{Type: kind}); err != nil && !errors.Is(err, errPhoneNotConnected) {
		log.Printf("電話機 %s に同期の状態を送れなかった: %v", phoneID, err)
	}
}

// familyUID は、Authorization の ID トークンから家族の uid を取る。
func (s *server) familyUID(w http.ResponseWriter, r *http.Request) (string, bool) {
	idToken, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || idToken == "" {
		http.Error(w, "Authorization ヘッダーに、家族の ID トークンを Bearer で入れてください", http.StatusUnauthorized)
		return "", false
	}
	token, err := s.firebase.Auth.VerifyIDToken(r.Context(), idToken)
	if err != nil {
		log.Printf("家族の ID トークンを確かめられなかった: %v", err)
		http.Error(w, "家族の ID トークンを確かめられなかった", http.StatusUnauthorized)
		return "", false
	}
	return token.UID, true
}
