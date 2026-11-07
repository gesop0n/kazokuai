package server

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"

	"cloud.google.com/go/firestore"
)

// watchedPersonsPath は、アプリが見守る方を登録するパスである。
// アプリは Authorization ヘッダーに家族の Firebase の ID トークンを入れ、本文に registration を JSON で入れて POST する。
const watchedPersonsPath = "/watched-persons"

// watchedPersons は、見守る方のドキュメントを置く Firestore のコレクションである。
const watchedPersons = "watchedPersons"

// watchedPerson は、Firestore の見守る方のドキュメントである。
type watchedPerson struct {
	// Name は見守る方の名前である。
	Name string `firestore:"name"`
	// CallName は、AI が見守る方を呼ぶときの呼び方である。
	CallName string `firestore:"callName"`
	// FamilyUIDs は、この見守る方に結び付いた家族の uid である。
	// セキュリティルールは、ここに uid がある家族にだけ、この見守る方を読ませる。
	FamilyUIDs []string `firestore:"familyUids"`
}

// registration は、見守る方を登録する頼みの本文である。
type registration struct {
	Name     string `json:"name"`
	CallName string `json:"callName"`
}

// registered は、登録した見守る方を返すレスポンスである。
type registered struct {
	ID string `json:"id"`
}

// maxRegistration は、登録の頼みの本文の上限である。名前と呼び方には十分に大きい。
const maxRegistration = 4 << 10

// errAlreadyRegistered は、家族にすでに見守る方がいるときである。この仕様では、1 人の家族が登録できる見守る方は 1 人までにする。
var errAlreadyRegistered = errors.New("この家族には、すでに見守る方がいる")

// registerWatchedPerson は、ID トークンを確かめた家族を家族の一覧に入れて、見守る方を作る。
func (s *server) registerWatchedPerson(w http.ResponseWriter, r *http.Request) {
	idToken, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !ok {
		http.Error(w, "Authorization ヘッダーに、家族の ID トークンを Bearer で入れてください", http.StatusUnauthorized)
		return
	}
	token, err := s.firebase.Auth.VerifyIDToken(r.Context(), idToken)
	if err != nil {
		log.Printf("家族の ID トークンを確かめられなかった: %v", err)
		http.Error(w, "家族の ID トークンを確かめられなかった", http.StatusUnauthorized)
		return
	}
	var req registration
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxRegistration)).Decode(&req); err != nil {
		http.Error(w, "本文を JSON で読めなかった", http.StatusBadRequest)
		return
	}
	person := watchedPerson{
		Name:       strings.TrimSpace(req.Name),
		CallName:   strings.TrimSpace(req.CallName),
		FamilyUIDs: []string{token.UID},
	}
	if person.Name == "" || person.CallName == "" {
		http.Error(w, "見守る方の名前と呼び方を入れてください", http.StatusBadRequest)
		return
	}
	id, err := createWatchedPerson(r.Context(), s.firebase.Firestore, person)
	if errors.Is(err, errAlreadyRegistered) {
		http.Error(w, err.Error(), http.StatusConflict)
		return
	}
	if err != nil {
		log.Printf("見守る方を登録できなかった: %v", err)
		http.Error(w, "見守る方を登録できなかった", http.StatusInternalServerError)
		return
	}
	log.Printf("見守る方を登録しました。この見守る方に電話をかけるときは、--watched-person %s で起動し直してください", id)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(registered{ID: id})
}

// createWatchedPerson は、家族にまだ見守る方がいなければ、見守る方のドキュメントを作ってその ID を返す。
// 確かめることと作ることを 1 つのトランザクションにするので、同時に 2 回頼まれても 1 人しか作らない。
func createWatchedPerson(ctx context.Context, store *firestore.Client, person watchedPerson) (string, error) {
	collection := store.Collection(watchedPersons)
	ref := collection.NewDoc()
	err := store.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		existing, err := tx.Documents(
			collection.Where("familyUids", "array-contains", person.FamilyUIDs[0]).Limit(1),
		).GetAll()
		if err != nil {
			return err
		}
		if len(existing) > 0 {
			return errAlreadyRegistered
		}
		return tx.Create(ref, person)
	})
	if err != nil {
		return "", err
	}
	return ref.ID, nil
}

// CheckWatchedPerson は、id の見守る方が Firestore にいて、名前と呼び方を読めることを確かめる。
func CheckWatchedPerson(ctx context.Context, firebase Firebase, id string) error {
	_, err := readWatchedPerson(ctx, firebase.Firestore, id)
	return err
}

// readWatchedPerson は、id の見守る方を Firestore から読む。
func readWatchedPerson(ctx context.Context, store *firestore.Client, id string) (watchedPerson, error) {
	doc, err := store.Collection(watchedPersons).Doc(id).Get(ctx)
	if err != nil {
		return watchedPerson{}, err
	}
	var person watchedPerson
	if err := doc.DataTo(&person); err != nil {
		return watchedPerson{}, err
	}
	return person, nil
}
