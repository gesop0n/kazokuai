package server

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// phonesCollection は、電話機のドキュメントを置く Firestore のコレクションである。
// ドキュメント ID は電話機の ID。アプリからは読めない。
const phonesCollection = "phones"

// phoneRecord は、Firestore の電話機のドキュメントである。
// 鍵そのものは置かず、ハッシュだけを置く。見守る方は、同期していないとき空である。
type phoneRecord struct {
	KeyHash         string    `firestore:"keyHash"`
	WatchedPersonID string    `firestore:"watchedPersonId"`
	RegisteredAt    time.Time `firestore:"registeredAt"`
	// SyncedAt は、この電話機を見守る方に結び付けた時刻である。同期していないときは空である。
	SyncedAt time.Time `firestore:"syncedAt,omitempty"`
}

// phoneIdentity は、ID と鍵で認証した電話機である。
// personID は、認証したときの結び付きである。空なら、まだ同期していない。
type phoneIdentity struct {
	phoneID  string
	personID string
}

type phoneContextKey struct{}

var phoneIdentityKey phoneContextKey

var (
	errUnknownPhone = errors.New("この電話機は登録されていません")
	errBadPhoneKey  = errors.New("鍵が違います")
	errPhoneKeyUsed = errors.New("この電話機は別の鍵で登録されている")
)

// registerPhone は、合言葉を確かめて電話機の ID と鍵を登録する。
// 鍵のハッシュを phones/{ID} に残す。同じ ID と鍵なら、結び付きを変えずに成功する。
// 同じ ID で鍵が違うときは断る。
func (s *server) registerPhone(w http.ResponseWriter, r *http.Request) {
	if !phoneSecretOK(r.Header.Get(protocol.PhoneSecretHeader), s.config.PhoneSecret) {
		http.Error(w, protocol.PhoneAnswerBadSecret, http.StatusUnauthorized)
		return
	}
	id := strings.TrimSpace(r.Header.Get(protocol.PhoneIDHeader))
	key := r.Header.Get(protocol.PhoneKeyHeader)
	if id == "" || key == "" {
		http.Error(w, "電話機の ID と鍵を入れてください", http.StatusBadRequest)
		return
	}
	if !validPhoneID(id) || !validPhoneKey(key) {
		http.Error(w, "電話機の ID が使えません", http.StatusBadRequest)
		return
	}
	created, err := s.savePhone(r.Context(), id, key)
	if errors.Is(err, errPhoneKeyUsed) {
		http.Error(w, protocol.PhoneAnswerBadKey, http.StatusConflict)
		return
	}
	if err != nil {
		log.Printf("電話機 %s を登録できなかった: %v", id, err)
		http.Error(w, "電話機を登録できなかった", http.StatusInternalServerError)
		return
	}
	if created {
		log.Printf("電話機を登録しました: %s", id)
	}
	w.Header().Set("Content-Type", "application/json")
	if created {
		w.WriteHeader(http.StatusCreated)
	} else {
		w.WriteHeader(http.StatusOK)
	}
	json.NewEncoder(w).Encode(struct {
		ID string `json:"id"`
	}{ID: id})
}

// savePhone は、ID が未登録ならハッシュを作り、同じ鍵なら何も変えず、違う鍵なら断る。
func (s *server) savePhone(ctx context.Context, id, key string) (created bool, err error) {
	ref := s.firebase.Firestore.Collection(phonesCollection).Doc(id)
	sum := hashPhoneKey(key)
	err = s.firebase.Firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		if status.Code(err) == codes.NotFound {
			created = true
			return tx.Create(ref, phoneRecord{
				KeyHash:         sum,
				WatchedPersonID: "",
				RegisteredAt:    s.now(),
			})
		}
		if err != nil {
			return err
		}
		created = false
		var record phoneRecord
		if err := doc.DataTo(&record); err != nil {
			return err
		}
		if subtle.ConstantTimeCompare([]byte(record.KeyHash), []byte(sum)) != 1 {
			return errPhoneKeyUsed
		}
		return nil
	})
	if err != nil {
		return false, err
	}
	return created, nil
}

// phoneByKey は、ID と鍵で電話機を認証する。
// 知らない ID と、鍵が違うときとで、答えを分ける。
func (s *server) phoneByKey(ctx context.Context, id, key string) (phoneIdentity, int, string, error) {
	if s.firebase.Firestore == nil {
		return phoneIdentity{}, http.StatusInternalServerError, "電話機を読めなかった", errors.New("Firestore がない")
	}
	if !validPhoneID(id) {
		return phoneIdentity{}, http.StatusNotFound, protocol.PhoneAnswerUnknownPhone, errUnknownPhone
	}
	doc, err := s.firebase.Firestore.Collection(phonesCollection).Doc(id).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return phoneIdentity{}, http.StatusNotFound, protocol.PhoneAnswerUnknownPhone, errUnknownPhone
	}
	if err != nil {
		log.Printf("電話機 %s を読めなかった: %v", id, err)
		return phoneIdentity{}, http.StatusInternalServerError, "電話機を読めなかった", err
	}
	var record phoneRecord
	if err := doc.DataTo(&record); err != nil {
		log.Printf("電話機 %s を読めなかった: %v", id, err)
		return phoneIdentity{}, http.StatusInternalServerError, "電話機を読めなかった", err
	}
	if !validPhoneKey(key) || subtle.ConstantTimeCompare([]byte(record.KeyHash), []byte(hashPhoneKey(key))) != 1 {
		return phoneIdentity{}, http.StatusUnauthorized, protocol.PhoneAnswerBadKey, errBadPhoneKey
	}
	return phoneIdentity{phoneID: id, personID: record.WatchedPersonID}, 0, "", nil
}

// phonePerson は、phones/{id} の今の見守る方を返す。文書が無いときは空で、エラーにしない。
func (s *server) phonePerson(ctx context.Context, phoneID string) (string, error) {
	doc, err := s.firebase.Firestore.Collection(phonesCollection).Doc(phoneID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	var record phoneRecord
	if err := doc.DataTo(&record); err != nil {
		return "", err
	}
	return record.WatchedPersonID, nil
}

func phoneIdentityFrom(ctx context.Context) phoneIdentity {
	identity, _ := ctx.Value(phoneIdentityKey).(phoneIdentity)
	return identity
}

// linkedPhoneID は、personID に結び付いている電話機の ID を返す。
// 結び付きが無いときは ok が false である。
func (s *server) linkedPhoneID(ctx context.Context, personID string) (phoneID string, ok bool, err error) {
	if s.firebase.Firestore == nil || personID == "" {
		return "", false, nil
	}
	docs, err := s.firebase.Firestore.Collection(phonesCollection).
		Where("watchedPersonId", "==", personID).
		Limit(1).
		Documents(ctx).
		GetAll()
	if err != nil {
		return "", false, err
	}
	if len(docs) == 0 {
		return "", false, nil
	}
	return docs[0].Ref.ID, true, nil
}

// personConnected は、見守る方に結び付いた電話機が、今電話を届けられるかを返す。
func (s *server) personConnected(ctx context.Context, personID string) bool {
	phoneID, linked, err := s.linkedPhoneID(ctx, personID)
	if err != nil {
		log.Printf("見守る方 %s の電話機を探せなかった: %v", personID, err)
		return false
	}
	if !linked {
		return false
	}
	return s.phones.hasPhone(phoneID)
}

// refuseOtherPerson は、電話機が結び付きと違う見守る方を名乗ったときに true を返す。
// 見守る方を名乗らないリクエストは、ここでは断らない。
func refuseOtherPerson(w http.ResponseWriter, identity phoneIdentity, named string) bool {
	if named == "" || named == identity.personID {
		return false
	}
	http.Error(w, protocol.PhoneAnswerOtherPerson, http.StatusForbidden)
	return true
}

func (s *server) now() time.Time {
	if s.clock == nil {
		return time.Now()
	}
	return s.clock.Now()
}

// hashPhoneKey は、電話機が作った乱数の鍵のハッシュである。鍵そのものは保存しない。
func hashPhoneKey(key string) string {
	sum := sha256.Sum256([]byte(key))
	return hex.EncodeToString(sum[:])
}

func validPhoneID(id string) bool {
	if len(id) < 1 || len(id) > 128 {
		return false
	}
	for _, r := range id {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '-', r == '_':
		default:
			return false
		}
	}
	return true
}

func validPhoneKey(key string) bool {
	return key != "" && len(key) <= 256
}
