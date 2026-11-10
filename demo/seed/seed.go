package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/auth"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// watchedPersonID は、見本の見守る方のドキュメント ID である。作り直しても変わらない。
const watchedPersonID = "tanaka-hana"

// judgeDisplayName は、08e の「あなたのお名前」である。Firebase Auth の表示名に入れる。
const judgeDisplayName = "田中 太郎"

// Request は、見本を書く先と、審査員のアカウントである。パスワードはログに出さない。
type Request struct {
	ProjectID     string
	Email         string
	Password      string
	FirestoreHost string
	AuthHost      string
	// Today は、見本の 1 週間が朝で終わる日である。日付は日本時間で読む。ゼロのときは、実行した日。
	Today time.Time
}

// Result は、作った審査員と見守る方である。
type Result struct {
	Email           string
	UID             string
	WatchedPersonID string
	Calls           int
	Missed          int
	Bookings        int
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

// Seed は、渡した Firebase に審査員と見本の電話と見本の予約を作る。
// 見本の 1 週間は、渡した日の朝で終わる。日を渡さないときは、実行した日の朝で終わる。
// 見本の予約は、その日の翌日以降に 3 件ある。タスクは作らない。
// もう一度実行すると、そのアカウントの電話と見本の予約をその日の見本に戻し、チュートリアルを見た記録を消す。
func Seed(ctx context.Context, store *firestore.Client, accounts *auth.Client, req Request) (Result, error) {
	user, err := upsertJudge(ctx, accounts, req.Email, req.Password)
	if err != nil {
		return Result{}, err
	}
	if err := releaseOtherPersons(ctx, store, user.UID); err != nil {
		return Result{}, err
	}
	person := store.Collection("watchedPersons").Doc(watchedPersonID)
	fields := map[string]any{
		"name":       samplePersonName,
		"callName":   sampleCallName,
		"familyUids": []string{user.UID},
	}
	// 見本を書き直しても、電話機との結び付きは残す。審査の前にもう一度実行しても、同期は取り消さない。
	kept, err := keptPhoneLink(ctx, person)
	if err != nil {
		return Result{}, err
	}
	for key, value := range kept {
		fields[key] = value
	}
	if _, err := person.Set(ctx, fields); err != nil {
		return Result{}, fmt.Errorf("見守る方を書けなかった: %w", err)
	}
	day := sampleDay(req)
	if err := deleteCalls(ctx, store, person); err != nil {
		return Result{}, err
	}
	calls := sampleCalls(day)
	missed := 0
	for _, call := range calls {
		if err := writeCall(ctx, store, person, call); err != nil {
			return Result{}, err
		}
		if call.missed {
			missed++
		}
	}
	// 見本の予約はここで直接書く。保存の道を通すとタスクができ、審査のあいだに鳴る。
	// 番号は、同じ ID の今の番号より 1 つ進める。1 に戻すと、直したあとの番号が
	// 動き続けている予定と重なり、もう一度直しても新しい時刻にかからない。
	bookings := sampleBookings(day)
	numbers, err := nextBookingNumbers(ctx, person, bookings)
	if err != nil {
		return Result{}, err
	}
	if err := deleteBookings(ctx, store, person); err != nil {
		return Result{}, err
	}
	for _, booking := range bookings {
		if err := writeBooking(ctx, store, person, booking, numbers[booking.id]); err != nil {
			return Result{}, err
		}
	}
	if err := resetTutorial(ctx, store, user.UID); err != nil {
		return Result{}, err
	}
	return Result{
		Email:           req.Email,
		UID:             user.UID,
		WatchedPersonID: watchedPersonID,
		Calls:           len(calls),
		Missed:          missed,
		Bookings:        len(bookings),
	}, nil
}

// resetTutorial は、この審査員がチュートリアルを見た記録を消す。
// 記録がなくても成功する。ほかの家族の記録は消さない。
func resetTutorial(ctx context.Context, store *firestore.Client, uid string) error {
	if _, err := store.Collection("tutorialSeen").Doc(uid).Delete(ctx); err != nil {
		return fmt.Errorf("チュートリアルの記録を戻せなかった: %w", err)
	}
	return nil
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
			DisplayName(judgeDisplayName).
			EmailVerified(true))
		if err != nil {
			return nil, fmt.Errorf("審査員のアカウントを作れなかった: %w", err)
		}
		return created, nil
	}
	updated, err := accounts.UpdateUser(ctx, user.UID, (&auth.UserToUpdate{}).
		Password(password).
		DisplayName(judgeDisplayName).
		EmailVerified(true))
	if err != nil {
		return nil, fmt.Errorf("審査員のアカウントを戻せなかった: %w", err)
	}
	return updated, nil
}

// keptPhoneLink は、見本を書き直しても残す、電話機との結び付きである。
// 結び付きが無いときと、文書がまだ無いときは nil を返す。
func keptPhoneLink(ctx context.Context, person *firestore.DocumentRef) (map[string]any, error) {
	snap, err := person.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("見守る方を読めなかった: %w", err)
	}
	id, _ := snap.Data()["phoneId"].(string)
	if id == "" {
		return nil, nil
	}
	kept := map[string]any{"phoneId": id}
	if at, ok := snap.Data()["syncedAt"].(time.Time); ok && !at.IsZero() {
		kept["syncedAt"] = at
	}
	return kept, nil
}

// releaseOtherPersons は、この審査員が結び付いている、見本以外の見守る方から審査員を外す。
// 審査員だけの文書は、電話と予約ごと消す。ほかの家族がいる文書は残し、家族の一覧から審査員だけ外す。
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
	// 予約を残すと、文書を消したあとも起動時の読み直しがタスクにする。
	if err := deleteBookings(ctx, store, person); err != nil {
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
	return deleteDocs(ctx, store, refs, "電話")
}

func deleteBookings(ctx context.Context, store *firestore.Client, person *firestore.DocumentRef) error {
	docs, err := person.Collection("bookings").Documents(ctx).GetAll()
	if err != nil {
		return fmt.Errorf("予約を読めなかった: %w", err)
	}
	refs := make([]*firestore.DocumentRef, 0, len(docs))
	for _, doc := range docs {
		refs = append(refs, doc.Ref)
	}
	return deleteDocs(ctx, store, refs, "予約")
}

// nextBookingNumbers は、見本の予約ごとに、次に書く番号を返す。
// 文書が無いときは 1、あるときは今の番号に 1 を足す。消す前に読む。
func nextBookingNumbers(ctx context.Context, person *firestore.DocumentRef, bookings []sampleBooking) (map[string]int64, error) {
	numbers := make(map[string]int64, len(bookings))
	for _, booking := range bookings {
		doc, err := person.Collection("bookings").Doc(booking.id).Get(ctx)
		if status.Code(err) == codes.NotFound {
			numbers[booking.id] = 1
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("予約 %s の番号を読めなかった: %w", booking.id, err)
		}
		number, ok := storedBookingNumber(doc.Data()["number"])
		if !ok {
			return nil, fmt.Errorf("予約 %s の番号を読めなかった", booking.id)
		}
		numbers[booking.id] = number + 1
	}
	return numbers, nil
}

func storedBookingNumber(value any) (int64, bool) {
	switch n := value.(type) {
	case int64:
		return n, true
	case int:
		return int64(n), true
	case float64:
		return int64(n), true
	default:
		return 0, false
	}
}

func writeBooking(ctx context.Context, store *firestore.Client, person *firestore.DocumentRef, booking sampleBooking, number int64) error {
	// Set は文書を置き換える。taskPending は書かない。
	// 見本にタスクは無く、印があると起動し直しがタスクを作ってしまう。
	_, err := person.Collection("bookings").Doc(booking.id).Set(ctx, map[string]any{
		"at":      booking.at,
		"message": booking.message,
		"script":  booking.script,
		"number":  number,
		"called":  false,
		// 見本はタスクを作らない。起動時の読み直しは、これを見てかけない。
		"sample": true,
	})
	if err != nil {
		return fmt.Errorf("予約 %s を書けなかった: %w", booking.id, err)
	}
	return nil
}

func deleteDocs(ctx context.Context, store *firestore.Client, refs []*firestore.DocumentRef, what string) error {
	const limit = 400
	for len(refs) > 0 {
		n := min(len(refs), limit)
		batch := store.Batch()
		for _, ref := range refs[:n] {
			batch.Delete(ref)
		}
		if _, err := batch.Commit(ctx); err != nil {
			return fmt.Errorf("%sを消せなかった: %w", what, err)
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
