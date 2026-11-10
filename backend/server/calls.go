package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// callsCollection は、見守る方の下に電話を置くサブコレクションである。
const callsCollection = "calls"

// utterancesCollection は、電話の下に発話を置くサブコレクションである。
const utterancesCollection = "utterances"

// maxCallReport は、電話の報告の本文の上限である。長い電話の文字起こしが入る。
const maxCallReport = 1 << 20

// firestoreBatchLimit は、1 回のバッチに入れる書き込みの数である。Firestore の上限は 500 である。
const firestoreBatchLimit = 400

// maxStartCall は、今すぐ通話の頼みの本文の上限である。伝えたいことと通話内容には十分に大きい。
const maxStartCall = 16 << 10

// startCallBody は、今すぐ通話を始める頼みの本文である。
type startCallBody struct {
	// Message は、家族が入れた伝えたいことである。
	Message string `json:"message"`
	// Script は、画面に出ている通話内容である。
	Script string `json:"script"`
}

// startedCall は、始めた電話の ID を返すレスポンスである。
type startedCall struct {
	ID string `json:"id"`
}

// apiError は、アプリが見分けるエラーの本文である。
type apiError struct {
	Error string `json:"error"`
}

// errNotFamily は、ログインした人に見守る方がいないときである。
var errNotFamily = errors.New("この家族には見守る方がいない")

// errCallInProgress は、見守る方の電話のどれかが呼び出し中か通話中のときである。
var errCallInProgress = errors.New("電話の最中")

// startCall は、ID トークンを確かめた家族の見守る方に、今すぐ電話をかける。
// 電話機がつながっていないときと、電話の最中は、電話の文書を作らない。
// 文書を作ったあとで結び付きが替わっていたときは、その文書を消して届かない。
func (s *server) startCall(w http.ResponseWriter, r *http.Request) {
	uid, ok := s.familyUID(w, r)
	if !ok {
		return
	}
	var req startCallBody
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxStartCall)).Decode(&req); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return
	}
	req.Message = strings.TrimSpace(req.Message)
	req.Script = strings.TrimSpace(req.Script)
	if req.Message == "" || req.Script == "" {
		http.Error(w, "伝えたいことと通話内容を入れてください", http.StatusBadRequest)
		return
	}
	personID, err := findFamilyPerson(r.Context(), s.firebase.Firestore, uid)
	if errors.Is(err, errNotFamily) {
		http.Error(w, "この見守る方の家族ではないので、電話を始められません", http.StatusForbidden)
		return
	}
	if err != nil {
		log.Printf("家族の見守る方を読めなかった: %v", err)
		http.Error(w, "見守る方を読めなかった", http.StatusInternalServerError)
		return
	}
	phoneID, linked, err := s.linkedPhoneID(r.Context(), personID)
	if err != nil {
		log.Printf("見守る方 %s の電話機を探せなかった: %v", personID, err)
		http.Error(w, "電話機を読めなかった", http.StatusInternalServerError)
		return
	}
	if !linked || !s.phones.hasPhone(phoneID) {
		s.logf("今すぐ通話を断りました。電話機がつながっていません。見守る方: %s", personID)
		writeAPIError(w, http.StatusConflict, protocol.PhoneNotConnected)
		return
	}
	ref, err := s.beginCall(r.Context(), personID, req.Message, req.Script)
	if errors.Is(err, errCallInProgress) {
		writeAPIError(w, http.StatusConflict, protocol.CallInProgress)
		return
	}
	if err != nil {
		log.Printf("電話を作れなかった: %v", err)
		http.Error(w, "電話を作れなかった", http.StatusInternalServerError)
		return
	}
	msg := protocol.PhoneMessage{Type: protocol.PhoneTypeCall, CallID: ref.ID}
	// 文書を作るあいだに電話機が替わっていることがある。届ける直前に、今の結び付きと一致するときだけ送る。
	err = s.sendToLinkedPhone(r.Context(), personID, phoneID, msg)
	if err != nil {
		s.discardCall(r.Context(), ref)
		if errors.Is(err, errPhoneNotConnected) {
			s.logf("今すぐ通話を断りました。電話機がつながっていません。見守る方: %s", personID)
			writeAPIError(w, http.StatusConflict, protocol.PhoneNotConnected)
			return
		}
		log.Printf("見守る方 %s の電話機を探せなかった: %v", personID, err)
		http.Error(w, "電話機を読めなかった", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(startedCall{ID: ref.ID})
}

// startWatchedCall は、ID と鍵で認証した電話機が、結び付いた見守る方の電話を始める。
// 同期していないときと、呼び出し中か通話中のときは、電話の文書を作らない。
// 伝えたいことは空にする。通話内容は、呼び方で挨拶してから話し相手になるよう書く。
// 電話には、見守る方から始めた印を付ける。答えは、その電話の ID である。
func (s *server) startWatchedCall(w http.ResponseWriter, r *http.Request) {
	identity := phoneIdentityFrom(r.Context())
	if identity.personID == "" {
		s.logf("見守る方からの電話を断りました。電話機が同期していません。電話機: %s", identity.phoneID)
		writeAPIError(w, http.StatusConflict, protocol.PhoneNotSynced)
		return
	}
	person, err := readWatchedPerson(r.Context(), s.firebase.Firestore, identity.personID)
	if err != nil {
		log.Printf("見守る方 %s を読めなかった: %v", identity.personID, err)
		http.Error(w, "見守る方を読めなかった", http.StatusInternalServerError)
		return
	}
	ref, err := s.createCall(r.Context(), identity.personID, callDraft{
		state:       protocol.StateRinging,
		script:      openingScript(person.CallName),
		fromWatched: true,
	})
	if errors.Is(err, errCallInProgress) {
		writeAPIError(w, http.StatusConflict, protocol.CallInProgress)
		return
	}
	if err != nil {
		log.Printf("電話を作れなかった: %v", err)
		http.Error(w, "電話を作れなかった", http.StatusInternalServerError)
		return
	}
	// 応答が届かなくても、呼び出しの上限まで通話中にならなければ、つながらなかったにする。
	// 呼び出し中のまま残すと、次の「＊」も今すぐ通話も塞ぐ。
	s.armWatchedRingLimit(identity.personID, ref.ID)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(protocol.StartedCall{ID: ref.ID})
}

// armWatchedRingLimit は、見守る方からの電話が呼び出し中のまま呼び出しの上限を過ぎたら、つながらなかったにする。
// それまでに通話中になっていれば、変えない。
func (s *server) armWatchedRingLimit(personID, callID string) {
	limit := s.config.RingTimeout
	if limit <= 0 {
		return
	}
	timer := s.newTimer(limit)
	go func() {
		select {
		case <-s.base.Done():
			timer.Stop()
		case <-timer.Chan():
			s.failIfStillRinging(personID, callID)
		}
	}()
}

// failIfStillRinging は、まだ呼び出し中の電話だけをつながらなかったにする。
func (s *server) failIfStillRinging(personID, callID string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	ref := s.callRef(personID, callID)
	err := s.firebase.Firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		if err != nil {
			return err
		}
		state, _ := doc.Data()["state"].(string)
		if state != protocol.StateRinging {
			return nil
		}
		return tx.Update(ref, []firestore.Update{{Path: "state", Value: protocol.StateFailed}})
	})
	if err != nil {
		log.Printf("見守る方からの電話 %s を %s にできなかった: %v", callID, protocol.StateFailed, err)
	}
}

// openingScript は、見守る方からの電話の始めの通話内容である。
// 呼び方で呼びかけ、かぞくAIだと伝え、何を話したいかを尋ねてから、話し相手として話すよう書く。
func openingScript(callName string) string {
	return strings.TrimSpace(callName) + "と呼びかけて、かぞくAIであることを伝えてください。何を話したいかを尋ねてから、話し相手として話してください。"
}

// sendToLinkedPhone は、linkMu を持って、今の結び付きが phoneID のときだけ msg を届ける。
// 届いたら、その電話機の認証コードを捨てる。有効なあいだの「＃」で同じコードを返さない。
// 読み直せないときは、そのエラーを返す。結び付きが違うときと、届かないときは errPhoneNotConnected を返す。
func (s *server) sendToLinkedPhone(ctx context.Context, personID, phoneID string, msg protocol.PhoneMessage) error {
	s.linkMu.Lock()
	defer s.linkMu.Unlock()
	nowID, nowLinked, err := s.linkedPhoneID(ctx, personID)
	if err != nil {
		return err
	}
	if !nowLinked || nowID != phoneID || !s.phones.hasPhone(nowID) {
		return errPhoneNotConnected
	}
	if err := s.phones.sendPhone(nowID, personID, msg); err != nil {
		s.logf("電話を届けられなかった。見守る方: %s、理由: %s", personID, oneLine(s.redact(err.Error())))
		return errPhoneNotConnected
	}
	s.syncs.dropCode(nowID)
	return nil
}

// discardCall は、電話機に届かなかった電話の文書を消す。
func (s *server) discardCall(ctx context.Context, ref *firestore.DocumentRef) {
	if _, err := ref.Delete(ctx); err != nil {
		log.Printf("届かなかった電話 %s を消せなかった: %v", ref.ID, err)
	}
}

// callDraft は、新しく作る電話の文書である。
type callDraft struct {
	state       string
	message     string
	script      string
	fromWatched bool
}

// beginCall は、見守る方の電話が呼び出し中でも通話中でもなければ、
// 呼び出し中の電話の文書を作ってその参照を返す。
// 読み取りと作成は 1 つのトランザクションなので、同時に 2 回頼まれても 1 つしか作らない。
func (s *server) beginCall(ctx context.Context, personID, message, script string) (*firestore.DocumentRef, error) {
	return s.createCall(ctx, personID, callDraft{
		state:   protocol.StateRinging,
		message: message,
		script:  script,
	})
}

// createCall は、見守る方の電話が呼び出し中でも通話中でもなければ、電話の文書を作ってその参照を返す。
// 読み取りと作成は 1 つのトランザクションなので、同時に 2 回頼まれても 1 つしか作らない。
func (s *server) createCall(ctx context.Context, personID string, draft callDraft) (*firestore.DocumentRef, error) {
	collection := s.firebase.Firestore.Collection(watchedPersons).Doc(personID).Collection(callsCollection)
	ref := collection.NewDoc()
	err := s.firebase.Firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		busy, err := tx.Documents(collection.Where("state", "in", []string{protocol.StateRinging, protocol.StateTalking}).Limit(1)).GetAll()
		if err != nil {
			return err
		}
		if len(busy) > 0 {
			return errCallInProgress
		}
		// createdAt はかけた時刻。出なかった電話には始まりの時刻がないので、通話記録はこの時刻を出す。
		fields := map[string]any{
			"state":     draft.state,
			"message":   draft.message,
			"script":    draft.script,
			"createdAt": s.clock.Now(),
		}
		if draft.fromWatched {
			fields[protocol.CallStartedByWatchedPerson] = true
		}
		return tx.Create(ref, fields)
	})
	if err != nil {
		return nil, err
	}
	return ref, nil
}

func writeAPIError(w http.ResponseWriter, status int, code string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(apiError{Error: code})
}

// findFamilyPerson は、uid の家族が結び付いている見守る方の ID を返す。
func findFamilyPerson(ctx context.Context, store *firestore.Client, uid string) (string, error) {
	docs, err := store.Collection(watchedPersons).Where("familyUids", "array-contains", uid).Limit(1).Documents(ctx).GetAll()
	if err != nil {
		return "", err
	}
	if len(docs) == 0 {
		return "", errNotFamily
	}
	return docs[0].Ref.ID, nil
}

// reportCall は、認証した電話の報告を受け取り、その電話に発話を足して、すぐに 202 Accepted を返す。
// ID と鍵で認証した電話機が、結び付きと違う見守る方を名乗ったときは断る。
func (s *server) reportCall(w http.ResponseWriter, r *http.Request) {
	var report protocol.CallReport
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxCallReport)).Decode(&report); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return
	}
	identity := phoneIdentityFrom(r.Context())
	if refuseOtherPerson(w, identity, report.WatchedPersonID) {
		return
	}
	if identity.personID == "" {
		http.Error(w, "この電話機は同期していません", http.StatusConflict)
		return
	}
	report.WatchedPersonID = identity.personID
	if report.CallID == "" {
		http.Error(w, "電話の ID を入れてください", http.StatusBadRequest)
		return
	}
	for _, utterance := range report.Utterances {
		if utterance.Speaker != protocol.SpeakerWatched && utterance.Speaker != protocol.SpeakerAI {
			http.Error(w, "発話の話した人は、見守る方か AI です", http.StatusBadRequest)
			return
		}
	}
	if err := addUtterances(r.Context(), s.firebase.Firestore, report); err != nil {
		log.Printf("電話を保存できなかった: %v", err)
		http.Error(w, "電話を保存できなかった", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusAccepted)
	// 応答を返してからまとめる。デバイスは Gemini を待たない。
	// リクエストの context は応答を返すと終わるので、まとめは別の context で作る。
	go s.makeSummary(report.WatchedPersonID, report.CallID, report)
}

// addUtterances は、すでに作ってある電話に、始まりの時刻と長さと発話を足す。
func addUtterances(ctx context.Context, store *firestore.Client, report protocol.CallReport) error {
	ref := store.Collection(watchedPersons).Doc(report.WatchedPersonID).Collection(callsCollection).Doc(report.CallID)
	if _, err := ref.Get(ctx); err != nil {
		return err
	}
	batch := store.Batch()
	ops := 0
	commit := func() error {
		if ops == 0 {
			return nil
		}
		if _, err := batch.Commit(ctx); err != nil {
			return err
		}
		batch = store.Batch()
		ops = 0
		return nil
	}
	batch.Set(ref, map[string]any{
		"startedAt":  report.StartedAt,
		"durationMs": report.DurationMs,
	}, firestore.MergeAll)
	ops++
	for i, utterance := range report.Utterances {
		if ops >= firestoreBatchLimit {
			if err := commit(); err != nil {
				return err
			}
		}
		batch.Set(ref.Collection(utterancesCollection).Doc(fmt.Sprintf("%04d", i)), map[string]any{
			"index":    i,
			"speaker":  utterance.Speaker,
			"offsetMs": utterance.OffsetMs,
			"text":     utterance.Text,
		})
		ops++
	}
	return commit()
}
