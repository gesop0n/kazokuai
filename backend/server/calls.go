package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"

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
func (s *server) startCall(w http.ResponseWriter, r *http.Request) {
	idToken, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok || idToken == "" {
		http.Error(w, "Authorization ヘッダーに、家族の ID トークンを Bearer で入れてください", http.StatusUnauthorized)
		return
	}
	token, err := s.firebase.Auth.VerifyIDToken(r.Context(), idToken)
	if err != nil {
		log.Printf("家族の ID トークンを確かめられなかった: %v", err)
		http.Error(w, "家族の ID トークンを確かめられなかった", http.StatusUnauthorized)
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
	personID, err := findFamilyPerson(r.Context(), s.firebase.Firestore, token.UID)
	if errors.Is(err, errNotFamily) {
		http.Error(w, "この見守る方の家族ではないので、電話を始められません", http.StatusForbidden)
		return
	}
	if err != nil {
		log.Printf("家族の見守る方を読めなかった: %v", err)
		http.Error(w, "見守る方を読めなかった", http.StatusInternalServerError)
		return
	}
	if !s.phones.connected(personID) {
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
	err = s.phones.send(personID, protocol.PhoneMessage{Type: protocol.PhoneTypeCall, CallID: ref.ID})
	if err != nil {
		// 指示が届かなかった電話は、残さない。家族には、つながらなかったと伝える。
		if _, delErr := ref.Delete(r.Context()); delErr != nil {
			log.Printf("届かなかった電話 %s を消せなかった: %v", ref.ID, delErr)
		}
		log.Printf("電話機に指示を送れなかった: %v", err)
		writeAPIError(w, http.StatusConflict, protocol.PhoneNotConnected)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(startedCall{ID: ref.ID})
}

// beginCall は、見守る方の電話が呼び出し中でも通話中でもなければ、
// 呼び出し中の電話の文書を作ってその参照を返す。
// 読み取りと作成は 1 つのトランザクションなので、同時に 2 回頼まれても 1 つしか作らない。
func (s *server) beginCall(ctx context.Context, personID, message, script string) (*firestore.DocumentRef, error) {
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
		return tx.Create(ref, map[string]any{
			"state":     protocol.StateRinging,
			"message":   message,
			"script":    script,
			"createdAt": s.clock.Now(),
		})
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

// reportCall は、合言葉を確かめた電話の報告を受け取り、その電話に発話を足して、すぐに 202 Accepted を返す。
func (s *server) reportCall(w http.ResponseWriter, r *http.Request) {
	var report protocol.CallReport
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxCallReport)).Decode(&report); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return
	}
	if report.CallID == "" || report.WatchedPersonID == "" {
		http.Error(w, "電話の ID と見守る方の ID を入れてください", http.StatusBadRequest)
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
