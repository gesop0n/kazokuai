package main

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/auth"
)

// watchedPersonID は、見本の見守る方のドキュメント ID である。作り直しても変わらない。
const watchedPersonID = "tanaka-hana"

// Request は、見本を書く先と、審査員のアカウントである。パスワードはログに出さない。
type Request struct {
	ProjectID     string
	Email         string
	Password      string
	FirestoreHost string
	AuthHost      string
}

// Result は、作った審査員と見守る方である。
type Result struct {
	Email           string
	UID             string
	WatchedPersonID string
	Calls           int
	Missed          int
}

func validateRequest(req Request) error {
	if strings.TrimSpace(req.ProjectID) == "" || strings.ContainsAny(req.ProjectID, " \t") || strings.HasPrefix(req.ProjectID, "-") {
		return errors.New("プロジェクトの ID が要ります。--project で渡してください")
	}
	if strings.TrimSpace(req.Email) == "" || !strings.Contains(req.Email, "@") {
		return errors.New("環境変数 JUDGE_EMAIL に審査員のメールアドレスを入れてください")
	}
	if req.Password == "" {
		return errors.New("環境変数 JUDGE_PASSWORD に審査員のパスワードを入れてください")
	}
	if len(req.Password) < 6 {
		return errors.New("審査員のパスワードは 6 文字以上にしてください")
	}
	emulator := req.FirestoreHost != "" || req.AuthHost != ""
	if strings.HasPrefix(req.ProjectID, "demo-") {
		if req.FirestoreHost == "" || req.AuthHost == "" {
			return errors.New("demo- のプロジェクトには FIRESTORE_EMULATOR_HOST と FIREBASE_AUTH_EMULATOR_HOST が要ります")
		}
		return nil
	}
	if emulator {
		return errors.New("エミュレーターの環境変数が設定されています。本番のプロジェクトには、FIRESTORE_EMULATOR_HOST と FIREBASE_AUTH_EMULATOR_HOST を外してから実行してください")
	}
	return nil
}

// Seed は、渡した Firebase に審査員と見本の電話を作る。もう一度実行すると、そのアカウントの電話を見本に戻す。
func Seed(ctx context.Context, store *firestore.Client, accounts *auth.Client, req Request) (Result, error) {
	user, err := upsertJudge(ctx, accounts, req.Email, req.Password)
	if err != nil {
		return Result{}, err
	}
	if err := releaseOtherPersons(ctx, store, user.UID); err != nil {
		return Result{}, err
	}
	person := store.Collection("watchedPersons").Doc(watchedPersonID)
	if _, err := person.Set(ctx, map[string]any{
		"name":       samplePersonName,
		"callName":   sampleCallName,
		"familyUids": []string{user.UID},
	}); err != nil {
		return Result{}, fmt.Errorf("見守る方を書けなかった: %w", err)
	}
	if err := deleteCalls(ctx, store, person); err != nil {
		return Result{}, err
	}
	calls := sampleCalls()
	missed := 0
	for _, call := range calls {
		if err := writeCall(ctx, store, person, call); err != nil {
			return Result{}, err
		}
		if call.missed {
			missed++
		}
	}
	return Result{
		Email:           req.Email,
		UID:             user.UID,
		WatchedPersonID: watchedPersonID,
		Calls:           len(calls),
		Missed:          missed,
	}, nil
}

func upsertJudge(ctx context.Context, accounts *auth.Client, email, password string) (*auth.UserRecord, error) {
	user, err := accounts.GetUserByEmail(ctx, email)
	if err != nil && !auth.IsUserNotFound(err) {
		return nil, fmt.Errorf("審査員のアカウントを読めなかった: %w", err)
	}
	if auth.IsUserNotFound(err) {
		created, err := accounts.CreateUser(ctx, (&auth.UserToCreate{}).
			Email(email).
			Password(password).
			EmailVerified(true))
		if err != nil {
			return nil, fmt.Errorf("審査員のアカウントを作れなかった: %w", err)
		}
		return created, nil
	}
	updated, err := accounts.UpdateUser(ctx, user.UID, (&auth.UserToUpdate{}).
		Password(password).
		EmailVerified(true))
	if err != nil {
		return nil, fmt.Errorf("審査員のパスワードを戻せなかった: %w", err)
	}
	return updated, nil
}

// releaseOtherPersons は、この審査員が結び付いている、見本以外の見守る方から審査員を外す。
// 審査員だけの文書は、電話ごと消す。ほかの家族がいる文書は残し、家族の一覧から審査員だけ外す。
func releaseOtherPersons(ctx context.Context, store *firestore.Client, uid string) error {
	docs, err := store.Collection("watchedPersons").Where("familyUids", "array-contains", uid).Documents(ctx).GetAll()
	if err != nil {
		return fmt.Errorf("審査員の見守る方を読めなかった: %w", err)
	}
	for _, doc := range docs {
		if doc.Ref.ID == watchedPersonID {
			continue
		}
		others := without(stringsOf(doc.Data()["familyUids"]), uid)
		if len(others) == 0 {
			if err := deletePerson(ctx, store, doc.Ref); err != nil {
				return err
			}
			continue
		}
		if _, err := doc.Ref.Update(ctx, []firestore.Update{{Path: "familyUids", Value: others}}); err != nil {
			return fmt.Errorf("見守る方 %s から審査員を外せなかった: %w", doc.Ref.ID, err)
		}
	}
	return nil
}

func deletePerson(ctx context.Context, store *firestore.Client, person *firestore.DocumentRef) error {
	if err := deleteCalls(ctx, store, person); err != nil {
		return err
	}
	if _, err := person.Delete(ctx); err != nil {
		return fmt.Errorf("見守る方 %s を消せなかった: %w", person.ID, err)
	}
	return nil
}

func deleteCalls(ctx context.Context, store *firestore.Client, person *firestore.DocumentRef) error {
	calls, err := person.Collection("calls").Documents(ctx).GetAll()
	if err != nil {
		return fmt.Errorf("電話を読めなかった: %w", err)
	}
	var refs []*firestore.DocumentRef
	for _, call := range calls {
		utterances, err := call.Ref.Collection("utterances").Documents(ctx).GetAll()
		if err != nil {
			return fmt.Errorf("会話を読めなかった: %w", err)
		}
		for _, utterance := range utterances {
			refs = append(refs, utterance.Ref)
		}
		refs = append(refs, call.Ref)
	}
	return deleteDocs(ctx, store, refs)
}

func deleteDocs(ctx context.Context, store *firestore.Client, refs []*firestore.DocumentRef) error {
	const limit = 400
	for len(refs) > 0 {
		n := min(len(refs), limit)
		batch := store.Batch()
		for _, ref := range refs[:n] {
			batch.Delete(ref)
		}
		if _, err := batch.Commit(ctx); err != nil {
			return fmt.Errorf("電話を消せなかった: %w", err)
		}
		refs = refs[n:]
	}
	return nil
}

func writeCall(ctx context.Context, store *firestore.Client, person *firestore.DocumentRef, call sampleCall) error {
	ref := person.Collection("calls").Doc(call.id)
	batch := store.Batch()
	batch.Set(ref, call.fields())
	for i, line := range call.lines {
		batch.Set(ref.Collection("utterances").Doc(fmt.Sprintf("%04d", i)), map[string]any{
			"index":    i,
			"speaker":  line.speaker,
			"offsetMs": line.offsetMs,
			"text":     line.text,
		})
	}
	if _, err := batch.Commit(ctx); err != nil {
		return fmt.Errorf("電話 %s を書けなかった: %w", call.id, err)
	}
	return nil
}

func without(values []string, drop string) []string {
	out := make([]string, 0, len(values))
	for _, value := range values {
		if value != drop {
			out = append(out, value)
		}
	}
	return out
}

func stringsOf(value any) []string {
	switch items := value.(type) {
	case []string:
		return append([]string(nil), items...)
	case []any:
		out := make([]string, 0, len(items))
		for _, item := range items {
			if text, ok := item.(string); ok {
				out = append(out, text)
			}
		}
		return out
	default:
		return nil
	}
}
