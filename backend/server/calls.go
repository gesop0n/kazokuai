package server

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

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

// reportCall は、認証なしで電話の報告を受け取り、電話と会話を保存して、すぐに 202 Accepted を返す。
func (s *server) reportCall(w http.ResponseWriter, r *http.Request) {
	if s.config.WatchedPerson == "" {
		http.Error(w, "電話をかける見守る方が決まっていません。--watched-person で見守る方の ID を指定して、バックエンドを起動し直してください", http.StatusServiceUnavailable)
		return
	}
	var report protocol.CallReport
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxCallReport)).Decode(&report); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return
	}
	for _, utterance := range report.Utterances {
		if utterance.Speaker != protocol.SpeakerWatched && utterance.Speaker != protocol.SpeakerAI {
			http.Error(w, "発話の話した人は、見守る方か AI です", http.StatusBadRequest)
			return
		}
	}
	id, err := saveCall(r.Context(), s.firebase.Firestore, s.config.WatchedPerson, report)
	if err != nil {
		log.Printf("電話を保存できなかった: %v", err)
		http.Error(w, "電話を保存できなかった", http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusAccepted)
	// 応答を返してからまとめる。デバイスは Gemini を待たない。
	// リクエストの context は応答を返すと終わるので、まとめは別の context で作る。
	go s.makeSummary(id, report)
}

// saveCall は、見守る方の下に電話と、その発話を保存し、電話の ID を返す。
func saveCall(ctx context.Context, store *firestore.Client, personID string, report protocol.CallReport) (string, error) {
	ref := store.Collection(watchedPersons).Doc(personID).Collection(callsCollection).NewDoc()
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
	})
	ops++
	for i, utterance := range report.Utterances {
		if ops >= firestoreBatchLimit {
			if err := commit(); err != nil {
				return "", err
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
	if err := commit(); err != nil {
		return "", err
	}
	return ref.ID, nil
}
