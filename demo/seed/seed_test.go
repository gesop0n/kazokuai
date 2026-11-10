package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/clock/clocktest"
	"github.com/gesop0n/kazokuai/internal/firebasetest"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// 時刻は日本時間。アプリは端末の現地時間で出す。審査は日本である。
var tokyo = time.FixedZone("Asia/Tokyo", 9*60*60)

// seedProject は、このテストだけのエミュレーターのプロジェクトである。
// go test はパッケージを並べて動かし、ほかのパッケージは demo-kazokuai に家族と電話を書く。
// 審査員のアカウントも見守る方も同じプロジェクトに置くと、その書き込みと一覧がぶつかる。
const seedProject = "demo-kazokuai-seed"

func TestValidateRequest(t *testing.T) {
	ok := Request{
		ProjectID: "kazokuai-prod",
		Email:     "judge@example.com",
		Password:  "judge-pass-1",
	}
	if err := validateRequest(ok); err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		name string
		req  Request
		want string
	}{
		{"project", Request{Email: ok.Email, Password: ok.Password}, "--project"},
		{"email", Request{ProjectID: ok.ProjectID, Password: ok.Password}, "JUDGE_EMAIL"},
		{"password", Request{ProjectID: ok.ProjectID, Email: ok.Email}, "JUDGE_PASSWORD"},
		{"short password", Request{ProjectID: ok.ProjectID, Email: ok.Email, Password: "short"}, "6"},
		{
			"demo without emulators",
			Request{ProjectID: "demo-kazokuai", Email: ok.Email, Password: ok.Password},
			"FIRESTORE_EMULATOR_HOST",
		},
		{
			"production with emulators",
			Request{
				ProjectID: ok.ProjectID, Email: ok.Email, Password: ok.Password,
				FirestoreHost: "127.0.0.1:8081", AuthHost: "127.0.0.1:9099",
			},
			"FIRESTORE_EMULATOR_HOST",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := validateRequest(tc.req)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("got %v, want %s", err, tc.want)
			}
		})
	}
}

func TestRunRequiresAnExplicitProject(t *testing.T) {
	t.Setenv("GOOGLE_CLOUD_PROJECT", "other-default-project")
	t.Setenv("CLOUDSDK_CORE_PROJECT", "other-default-project")
	t.Setenv("JUDGE_EMAIL", "judge@example.com")
	t.Setenv("JUDGE_PASSWORD", "judge-pass-1")
	err := run(context.Background(), nil)
	if err == nil || !strings.Contains(err.Error(), "--project") {
		t.Fatalf("got %v", err)
	}
}

func TestSeedCreatesTheWeekAndResetsIt(t *testing.T) {
	store, accounts := openEmulator(t)
	ctx := t.Context()
	const (
		email = "judge-seed@example.com"
		first = "judge-pass-1"
		next  = "judge-pass-2"
	)

	// 見本の中身を確かめる日。実行した日にはしない。
	today := time.Date(2026, 11, 5, 8, 0, 0, 0, tokyo)
	got := seedJudge(t, ctx, store, accounts, email, first, today)
	if got.WatchedPersonID != "tanaka-hana" {
		t.Fatalf("見守る方の ID = %s", got.WatchedPersonID)
	}
	assertJudgeName(t, ctx, accounts, got.UID)
	if signInStatus(t, email, first) != http.StatusOK {
		t.Fatal("最初のパスワードで審査員がログインできなかった")
	}
	personRef := store.Collection("watchedPersons").Doc("tanaka-hana")
	morningID := assertSampleWeek(t, ctx, personRef, got.UID)

	// 審査で増えた電話と、別の見守る方を、もう一度の実行で見本に戻す。
	if _, err := personRef.Collection("calls").Doc(morningID).Update(ctx, []firestore.Update{
		{Path: "summary.headline", Value: "変わったまとめ"},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := personRef.Collection("calls").Doc("extra").Set(ctx, map[string]any{
		"state":     protocol.StateEnded,
		"startedAt": time.Date(2026, 11, 6, 9, 0, 0, 0, tokyo),
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Collection("watchedPersons").Doc("judge-extra").Set(ctx, map[string]any{
		"name": "別の人", "callName": "別", "familyUids": []string{got.UID},
	}); err != nil {
		t.Fatal(err)
	}

	// 別の家族は、ほかのパッケージが使う Auth ではなく、このプロジェクトに作る。
	other, err := accounts.CreateUser(ctx, (&auth.UserToCreate{}).
		Email("other-"+strings.ToLower(rand.Text())+"@example.com").
		Password("other-pass-1"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Collection("watchedPersons").Doc("other-family").Set(ctx, map[string]any{
		"name": "別の家族の見守る方", "callName": "タロウさん", "familyUids": []string{other.UID},
	}); err != nil {
		t.Fatal(err)
	}
	shared := store.Collection("watchedPersons").Doc("shared")
	if _, err := shared.Set(ctx, map[string]any{
		"name": "共有", "callName": "共有さん", "familyUids": []string{got.UID, other.UID},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := shared.Collection("calls").Doc("keep").Set(ctx, map[string]any{
		"state": protocol.StateEnded, "startedAt": time.Date(2026, 11, 1, 8, 0, 0, 0, tokyo),
	}); err != nil {
		t.Fatal(err)
	}

	if _, err := store.Collection("tutorialSeen").Doc(got.UID).Set(ctx, map[string]any{"seen": true}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Collection("tutorialSeen").Doc(other.UID).Set(ctx, map[string]any{"seen": true}); err != nil {
		t.Fatal(err)
	}
	if _, err := accounts.UpdateUser(ctx, got.UID, (&auth.UserToUpdate{}).DisplayName("別の名前")); err != nil {
		t.Fatal(err)
	}
	again := seedJudge(t, ctx, store, accounts, email, next, today)
	if again.WatchedPersonID != got.WatchedPersonID || again.UID != got.UID {
		t.Fatalf("戻したあとの ID = %+v, 最初 = %+v", again, got)
	}
	assertJudgeName(t, ctx, accounts, again.UID)
	if signInStatus(t, email, next) != http.StatusOK {
		t.Fatal("新しいパスワードで審査員がログインできなかった")
	}
	if signInStatus(t, email, first) == http.StatusOK {
		t.Fatal("古いパスワードのままログインできた")
	}
	restored := assertSampleWeek(t, ctx, personRef, got.UID)
	if restored != morningID {
		t.Fatalf("朝の電話の ID = %s, 最初 = %s", restored, morningID)
	}
	if _, err := personRef.Collection("calls").Doc("extra").Get(ctx); err == nil {
		t.Fatal("足した電話が残っている")
	}
	if _, err := store.Collection("watchedPersons").Doc("judge-extra").Get(ctx); err == nil {
		t.Fatal("審査員だけの余分な見守る方が残っている")
	}

	otherDoc, err := store.Collection("watchedPersons").Doc("other-family").Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if otherDoc.Data()["name"] != "別の家族の見守る方" {
		t.Fatalf("別の家族の見守る方 = %v", otherDoc.Data())
	}
	sharedDoc, err := shared.Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if uids := stringsOf(sharedDoc.Data()["familyUids"]); len(uids) != 1 || uids[0] != other.UID {
		t.Fatalf("共有の家族 = %v", sharedDoc.Data()["familyUids"])
	}
	if _, err := shared.Collection("calls").Doc("keep").Get(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Collection("tutorialSeen").Doc(got.UID).Get(ctx); err == nil {
		t.Fatal("審査員のチュートリアルの記録が残っている")
	}
	otherSeen, err := store.Collection("tutorialSeen").Doc(other.UID).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if otherSeen.Data()["seen"] != true {
		t.Fatalf("別の家族のチュートリアル = %v", otherSeen.Data())
	}
}

func TestSeedKeepsThePhoneLink(t *testing.T) {
	store, accounts := openEmulator(t)
	ctx := t.Context()
	const email = "judge-link@example.com"
	today := time.Date(2026, 11, 5, 8, 0, 0, 0, tokyo)
	seedJudge(t, ctx, store, accounts, email, "judge-pass-1", today)

	person := store.Collection("watchedPersons").Doc("tanaka-hana")
	syncedAt := time.Date(2026, 11, 4, 3, 0, 0, 0, time.UTC)
	if _, err := person.Update(ctx, []firestore.Update{
		{Path: "name", Value: "変わった名前"},
		{Path: "phoneId", Value: "phone-judge"},
		{Path: "syncedAt", Value: syncedAt},
	}); err != nil {
		t.Fatal(err)
	}

	seedJudge(t, ctx, store, accounts, email, "judge-pass-1", today)
	doc, err := person.Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	data := doc.Data()
	if data["name"] != samplePersonName {
		t.Fatalf("名前 = %v, want %s", data["name"], samplePersonName)
	}
	if data["phoneId"] != "phone-judge" {
		t.Fatalf("電話機 = %v, want phone-judge", data["phoneId"])
	}
	at, ok := data["syncedAt"].(time.Time)
	if !ok || !at.Equal(syncedAt) {
		t.Fatalf("結び付けた時刻 = %v, want %v", data["syncedAt"], syncedAt)
	}
}

func assertJudgeName(t *testing.T, ctx context.Context, accounts *auth.Client, uid string) {
	t.Helper()
	user, err := accounts.GetUser(ctx, uid)
	if err != nil {
		t.Fatal(err)
	}
	if user.DisplayName != judgeDisplayName {
		t.Fatalf("審査員の名前 = %q", user.DisplayName)
	}
}

func TestSeedMovesTheWeekWhenRunOnAnotherDay(t *testing.T) {
	store, accounts := openEmulator(t)
	ctx := t.Context()
	const email = "judge-week@example.com"
	// 朝より前の時刻でも、その日の朝で終わる。
	first := time.Date(2026, 11, 10, 8, 30, 0, 0, tokyo)
	second := time.Date(2026, 11, 12, 7, 15, 0, 0, tokyo)

	seedJudge(t, ctx, store, accounts, email, "judge-pass-1", first)
	person := store.Collection("watchedPersons").Doc("tanaka-hana")
	assertWeekEndsOnMorning(t, ctx, person,
		time.Date(2026, 11, 10, 9, 2, 0, 0, tokyo),
		time.Date(2026, 11, 7, 9, 0, 0, 0, tokyo),
	)

	seedJudge(t, ctx, store, accounts, email, "judge-pass-1", second)
	assertWeekEndsOnMorning(t, ctx, person,
		time.Date(2026, 11, 12, 9, 2, 0, 0, tokyo),
		time.Date(2026, 11, 9, 9, 0, 0, 0, tokyo),
	)
	if callAt(t, ctx, person, time.Date(2026, 11, 5, 9, 0, 0, 0, tokyo)) {
		t.Fatal("11月5日の電話が残っている")
	}
	if callAt(t, ctx, person, time.Date(2026, 11, 10, 9, 2, 0, 0, tokyo)) {
		t.Fatal("11月10日の朝の電話が残っている")
	}
}

func TestSeedReplacesSampleBookingsAfterTheRunDay(t *testing.T) {
	store, accounts := openEmulator(t)
	ctx := t.Context()
	const email = "judge-bookings@example.com"
	// 朝より前でも、その日の翌日以降に入れる。
	today := time.Date(2026, 11, 10, 7, 15, 0, 0, tokyo)
	got := seedJudge(t, ctx, store, accounts, email, "judge-pass-1", today)
	person := store.Collection("watchedPersons").Doc("tanaka-hana")
	// 前のテストが残した番号に依存しない。文書が無いときは 1 から始まる。
	if err := deletePersonBookings(t, ctx, person); err != nil {
		t.Fatal(err)
	}
	seedJudge(t, ctx, store, accounts, email, "judge-pass-1", today)
	assertSampleBookings(t, ctx, person, today, map[string]int64{
		"話し相手": 1, "薬と戸締まりの確認": 1, "週末に帰ると伝える": 1,
	})

	docs, err := person.Collection("bookings").Documents(ctx).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := docs[0].Ref.Update(ctx, []firestore.Update{{Path: "message", Value: "書き換えた"}}); err != nil {
		t.Fatal(err)
	}
	if _, err := person.Collection("bookings").Doc("extra").Set(ctx, map[string]any{
		"at":      time.Date(2026, 11, 11, 15, 0, 0, 0, tokyo),
		"message": "余分な予約",
		"script":  "余分です。",
		"number":  int64(1),
		"called":  false,
	}); err != nil {
		t.Fatal(err)
	}
	// 直したあとの番号を 1 に戻すと、次の編集が前の予定と重なる。
	if _, err := person.Collection("bookings").Doc("sample-talk").Update(ctx, []firestore.Update{
		{Path: "number", Value: int64(7)},
	}); err != nil {
		t.Fatal(err)
	}
	// 審査員だけの見守る方に予約が残ると、起動時にタスクになる。
	extra := store.Collection("watchedPersons").Doc("judge-booking-extra")
	if _, err := extra.Set(ctx, map[string]any{
		"name": "別の人", "callName": "別", "familyUids": []string{got.UID},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := extra.Collection("bookings").Doc("soon").Set(ctx, map[string]any{
		"at":      time.Date(2026, 11, 11, 16, 0, 0, 0, tokyo),
		"message": "別の見守る方",
		"script":  "別の人への予約です。",
		"number":  int64(1),
		"called":  false,
	}); err != nil {
		t.Fatal(err)
	}

	later := time.Date(2026, 11, 12, 21, 0, 0, 0, tokyo)
	seedJudge(t, ctx, store, accounts, email, "judge-pass-1", later)
	assertSampleBookings(t, ctx, person, later, map[string]int64{
		"話し相手": 8, "薬と戸締まりの確認": 2, "週末に帰ると伝える": 2,
	})
	if _, err := extra.Collection("bookings").Doc("soon").Get(ctx); err == nil {
		t.Fatal("消した見守る方の予約が残っている")
	}
}

func TestReseededSampleRingsAtTheEditedTime(t *testing.T) {
	store, accounts := openEmulator(t)
	ctx := t.Context()
	const email = "judge-reseed-ring@example.com"
	now := time.Date(2026, 11, 10, 7, 15, 0, 0, tokyo)
	seedJudge(t, ctx, store, accounts, email, "judge-pass-1", now)
	person := store.Collection("watchedPersons").Doc(watchedPersonID)
	before, err := person.Collection("bookings").Doc("sample-talk").Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	number := asInt(before.Data()["number"])
	clk := clocktest.New(now)
	handler := server.New(server.Config{
		ProjectID:   seedProject,
		PhoneSecret: protocol.DevPhoneSecret,
	}, server.Firebase{Firestore: store, Auth: accounts}, nil, nil, clk)
	srv := httptest.NewServer(handler)
	t.Cleanup(func() {
		handler.Stop()
		srv.Close()
	})
	conn := dialSeedPhone(t, store, srv.URL, watchedPersonID)
	calls := readSeedPhoneCalls(conn)
	waitSeedConnected(t, handler, watchedPersonID)
	token := signInToken(t, email, "judge-pass-1")

	later := now.Add(time.Hour)
	editSeedBooking(t, srv.URL, token, "sample-talk", later, "一時間後", "ハナさん、一時間後です。")
	waitSeedDeadline(t, clk, later)

	seedJudge(t, ctx, store, accounts, email, "judge-pass-1", now)
	// 入れ直しはパスワードを設定し直す。エミュレーターは取り消しを秒で見るので、前の ID トークンは使えない。
	token = signInToken(t, email, "judge-pass-1")
	doc, err := person.Collection("bookings").Doc("sample-talk").Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	// 編集で 1 つ進み、入れ直しでさらにもう 1 つ進む。前の番号には戻さない。
	if _, ok := doc.Data()["taskPending"]; ok || doc.Data()["sample"] != true || asInt(doc.Data()["number"]) != number+2 {
		t.Fatalf("入れ直し = sample %v number %v taskPending %v, want number %d", doc.Data()["sample"], doc.Data()["number"], doc.Data()["taskPending"], number+2)
	}

	near := now.Add(3 * time.Minute)
	const script = "ハナさん、お薬は飲みましたか。"
	editSeedBooking(t, srv.URL, token, "sample-talk", near, "薬の確認", script)
	waitSeedDeadline(t, clk, near)
	clk.Advance(3 * time.Minute)
	got := receiveSeedCall(t, calls)
	if callScript(t, ctx, person, got.CallID) != script {
		t.Fatalf("通話内容 = %v", callScript(t, ctx, person, got.CallID))
	}
}

// assertSampleBookings は、見本の予約が day の翌日以降に 3 件あり、タスクが無いことを確かめる。
// numbers は、伝えたいことごとの予約番号である。中身はモックの予約である。
// モックの「今日」は実行した日には置かない。taskPending は付けない。
func assertSampleBookings(t *testing.T, ctx context.Context, person *firestore.DocumentRef, day time.Time, numbers map[string]int64) {
	t.Helper()
	docs, err := person.Collection("bookings").Documents(ctx).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(docs) != 3 {
		t.Fatalf("予約 = %d 件, want 3", len(docs))
	}
	y, m, d := day.In(tokyo).Date()
	want := []struct {
		at      time.Time
		message string
		script  string
	}{
		{time.Date(y, m, d+1, 12, 0, 0, 0, tokyo), "話し相手", "「ハナさん、こんにちは。\n体調はいかがですか。」"},
		{time.Date(y, m, d+1, 19, 0, 0, 0, tokyo), "薬と戸締まりの確認", "「ハナさん、こんばんは。\n夜のお薬は飲みましたか。\n戸締まりもご確認ください。」"},
		{time.Date(y, m, d+3, 10, 0, 0, 0, tokyo), "週末に帰ると伝える", "「ハナさん、ご家族からご伝言です。\n週末に帰るそうです。」"},
	}
	found := map[string]bool{}
	runDay := time.Date(y, m, d, 0, 0, 0, 0, tokyo)
	for _, doc := range docs {
		fields := doc.Data()
		message, _ := fields["message"].(string)
		var match *struct {
			at      time.Time
			message string
			script  string
		}
		for i := range want {
			if want[i].message == message {
				match = &want[i]
				break
			}
		}
		if match == nil {
			t.Fatalf("見本にない予約がある: %s", message)
		}
		found[message] = true
		at, _ := fields["at"].(time.Time)
		if !at.Equal(match.at) || fields["script"] != match.script {
			t.Fatalf("%s = %v / %v", message, at, fields["script"])
		}
		by, bm, bd := at.In(tokyo).Date()
		if !time.Date(by, bm, bd, 0, 0, 0, 0, tokyo).After(runDay) {
			t.Fatalf("%s の日 = %v, want %s の翌日以降", message, at, runDay.Format("2006-01-02"))
		}
		// 見本はタスクを作らない。かけた印も、かけた電話も、登録待ちの印も無い。
		if _, ok := fields["taskPending"]; ok || fields["sample"] != true || fields["called"] != false || asInt(fields["number"]) != numbers[message] {
			t.Fatalf("%s のタスク = sample %v called %v number %v taskPending %v", message, fields["sample"], fields["called"], fields["number"], fields["taskPending"])
		}
		if id, _ := fields["callId"].(string); id != "" {
			t.Fatalf("%s にかけた電話がある: %s", message, id)
		}
	}
	for _, item := range want {
		if !found[item.message] {
			t.Errorf("予約がない: %s", item.message)
		}
	}
}

func assertWeekEndsOnMorning(t *testing.T, ctx context.Context, person *firestore.DocumentRef, morning, missedAt time.Time) {
	t.Helper()
	calls, err := person.Collection("calls").Documents(ctx).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 7 {
		t.Fatalf("電話 = %d 件, want 7", len(calls))
	}
	var missed int
	var latest time.Time
	var latestCall *firestore.DocumentSnapshot
	for _, call := range calls {
		fields := call.Data()
		if fields["state"] == protocol.StateMissed {
			missed++
			got, _ := fields["createdAt"].(time.Time)
			if !got.Equal(missedAt) {
				t.Fatalf("出なかった時刻 = %v, want %v", got, missedAt)
			}
			continue
		}
		at, _ := fields["startedAt"].(time.Time)
		if latestCall == nil || at.After(latest) {
			latest = at
			latestCall = call
		}
	}
	if missed != 1 {
		t.Fatalf("出なかった電話 = %d 件", missed)
	}
	if latestCall == nil || !latest.Equal(morning) {
		t.Fatalf("いちばん新しい電話 = %v, want %v", latest, morning)
	}
	assertReplyCard(t, ctx, latestCall.Ref)
}

func callAt(t *testing.T, ctx context.Context, person *firestore.DocumentRef, at time.Time) bool {
	t.Helper()
	calls, err := person.Collection("calls").Documents(ctx).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	for _, call := range calls {
		fields := call.Data()
		if started, ok := fields["startedAt"].(time.Time); ok && started.Equal(at) {
			return true
		}
		if created, ok := fields["createdAt"].(time.Time); ok && created.Equal(at) {
			return true
		}
	}
	return false
}

func seedJudge(t *testing.T, ctx context.Context, store *firestore.Client, accounts *auth.Client, email, password string, today time.Time) Result {
	t.Helper()
	req := Request{
		ProjectID:     seedProject,
		Email:         email,
		Password:      password,
		FirestoreHost: os.Getenv("FIRESTORE_EMULATOR_HOST"),
		AuthHost:      os.Getenv("FIREBASE_AUTH_EMULATOR_HOST"),
		Today:         today,
	}
	if err := validateRequest(req); err != nil {
		t.Fatal(err)
	}
	got, err := Seed(ctx, store, accounts, req)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

func assertSampleWeek(t *testing.T, ctx context.Context, person *firestore.DocumentRef, uid string) string {
	t.Helper()
	doc, err := person.Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	data := doc.Data()
	if data["name"] != "田中 ハナ" || data["callName"] != "ハナさん" {
		t.Fatalf("見守る方 = %v", data)
	}
	if uids := stringsOf(data["familyUids"]); len(uids) != 1 || uids[0] != uid {
		t.Fatalf("家族 = %v, want %s", data["familyUids"], uid)
	}

	calls, err := person.Collection("calls").Documents(ctx).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 7 {
		t.Fatalf("電話 = %d 件, want 7", len(calls))
	}

	wantAnswered := []answeredCall{
		{time.Date(2026, 10, 31, 9, 0, 0, 0, tokyo), 22 * 60 * 1000, "庭の菊が咲き始めた話をした", "話し相手", "菊", "庭の菊が咲き始めたよ。"},
		{time.Date(2026, 11, 1, 12, 0, 0, 0, tokyo), 31 * 60 * 1000, "お米が残り少ないと相談があった", "話し相手", "お米", "お米が残り少ないの。"},
		{time.Date(2026, 11, 3, 9, 0, 0, 0, tokyo), 18 * 60 * 1000, "お孫さんの運動会の話がはずんだ", "話し相手", "運動会", "お孫さんの運動会の話でね、はずんだの。"},
		{time.Date(2026, 11, 4, 12, 0, 0, 0, tokyo), 9 * 60 * 1000, "テレビの映し方を案内して解決", "操作案内", "テレビ", "映らないのよ。"},
		{time.Date(2026, 11, 4, 19, 0, 0, 0, tokyo), 3 * 60 * 1000, "夕飯は大根の煮物。夜の薬も飲んだ", "体調", "大根", "大根の煮物を食べたよ。"},
		{time.Date(2026, 11, 5, 9, 2, 0, 0, tokyo), 6*60*1000 + 12*1000, "朝ごはんを食べ、薬も飲んだそうです。膝の痛みを少し気にしています。", "体調", "膝", "よく眠れたよ。朝ごはんも食べたしね。"},
	}

	var missed int
	var morningID string
	found := map[string]bool{}
	for _, call := range calls {
		fields := call.Data()
		if fields["state"] == protocol.StateMissed {
			missed++
			if _, ok := fields["startedAt"]; ok {
				t.Fatal("出なかった電話に始まりの時刻がある")
			}
			got, _ := fields["createdAt"].(time.Time)
			want := time.Date(2026, 11, 2, 9, 0, 0, 0, tokyo)
			if !got.Equal(want) {
				t.Fatalf("出なかった時刻 = %v, want %v", got, want)
			}
			utterances := utteranceTexts(t, ctx, call.Ref)
			if len(utterances) != 0 {
				t.Fatalf("出なかった電話の会話 = %v", utterances)
			}
			continue
		}
		summary := nested(t, fields["summary"])
		headline, _ := summary["headline"].(string)
		at, _ := fields["startedAt"].(time.Time)
		var match *answeredCall
		for i := range wantAnswered {
			if at.Equal(wantAnswered[i].at) {
				match = &wantAnswered[i]
				break
			}
		}
		if match == nil {
			t.Fatalf("見本にない電話がある: %v %s", at, headline)
		}
		found[match.headline] = true
		if headline != match.headline || summary["topic"] != match.topic || asInt(fields["durationMs"]) != match.durationMs {
			t.Fatalf("%v の電話 = %s / %v / %v", match.at, headline, summary["topic"], fields["durationMs"])
		}
		if fields["summaryState"] != "作れた" {
			t.Fatalf("%s のまとめの状態 = %v", headline, fields["summaryState"])
		}
		lines := utteranceTexts(t, ctx, call.Ref)
		if !containsWord(lines, match.word) {
			t.Fatalf("%s の会話に %s がない: %v", headline, match.word, lines)
		}
		quote := nested(t, summary["quote"])
		if quote["text"] != match.quote || !containsWord(lines, match.quote) {
			t.Fatalf("%s の本人の言葉 = %v", headline, quote)
		}
		if at.Equal(time.Date(2026, 11, 5, 9, 2, 0, 0, tokyo)) {
			morningID = call.Ref.ID
			assertMorningCall(t, ctx, call.Ref, fields, summary)
			assertReplyCard(t, ctx, call.Ref)
		}
		if at.Equal(time.Date(2026, 11, 4, 19, 0, 0, 0, tokyo)) {
			meal := nested(t, summary["meal"])
			health := nested(t, summary["health"])
			sleep := nested(t, summary["sleep"])
			if meal["status"] != "話した" || health["status"] != "話した" || sleep["status"] != "話していない" {
				t.Fatalf("夜の電話の今日の様子 = 食事 %v 体調 %v 睡眠 %v", meal, health, sleep)
			}
			if health["concerning"] == true {
				t.Fatal("夜の電話の体調が気になるになっている")
			}
		}
	}
	if missed != 1 {
		t.Fatalf("出なかった電話 = %d 件", missed)
	}
	if morningID == "" {
		t.Fatal("11月5日 9:02 の電話がない")
	}
	for _, want := range wantAnswered {
		if !found[want.headline] {
			t.Errorf("まとめがない: %s", want.headline)
		}
	}
	return morningID
}

type answeredCall struct {
	at         time.Time
	durationMs int64
	headline   string
	topic      string
	word       string
	quote      string
}

func containsWord(lines []string, word string) bool {
	for _, line := range lines {
		if strings.Contains(line, word) {
			return true
		}
	}
	return false
}

func assertMorningCall(t *testing.T, ctx context.Context, ref *firestore.DocumentRef, fields, summary map[string]any) {
	t.Helper()
	if fields["summaryState"] != "作れた" {
		t.Fatalf("まとめの状態 = %v", fields["summaryState"])
	}
	if asInt(fields["durationMs"]) != 6*60*1000+12*1000 {
		t.Fatalf("長さ = %v", fields["durationMs"])
	}
	if summary["topic"] != "体調" {
		t.Fatalf("話の種類 = %v", summary["topic"])
	}
	quote := nested(t, summary["quote"])
	if quote["text"] != "よく眠れたよ。朝ごはんも食べたしね。" || asInt(quote["offsetMs"]) != 11*1000 {
		t.Fatalf("本人の言葉 = %v", quote)
	}
	meal := nested(t, summary["meal"])
	sleep := nested(t, summary["sleep"])
	health := nested(t, summary["health"])
	if meal["status"] != "話した" || meal["said"] != "朝ごはんを食べた" || meal["quote"] != "朝ごはんも食べたしね" {
		t.Fatalf("食事 = %v", meal)
	}
	if sleep["status"] != "話した" || sleep["said"] != "よく眠れた" || sleep["quote"] != "よく眠れたよ" {
		t.Fatalf("睡眠 = %v", sleep)
	}
	if health["status"] != "話した" || health["said"] != "膝が痛い。階段がつらい" || health["concerning"] != true {
		t.Fatalf("体調 = %v", health)
	}
	points, _ := summary["points"].([]any)
	var texts []string
	for _, point := range points {
		item := nested(t, point)
		texts = append(texts, item["text"].(string))
	}
	wantPoints := []string{
		"朝ごはんを食べ、よく眠れたそうです",
		"昨日の夕方から膝が痛く、階段がつらいそうです",
		"朝の薬は飲んだと話しています",
	}
	if strings.Join(texts, "\n") != strings.Join(wantPoints, "\n") {
		t.Fatalf("まとめの点 = %v", texts)
	}
	wantLines := []string{
		"おはようございます、ハナさん。昨夜はよく眠れましたか。",
		"よく眠れたよ。朝ごはんも食べたしね。",
		"それは何よりです。お体の具合はいかがですか。",
		"昨日の夕方から膝が痛くてね。階段がつらいの。",
		"それはおつらいですね。美咲さんにもお伝えしておきましょうか。",
		"そうね、お願いしようかな。",
		"朝の薬は飲みましたか。",
		"飲んだよ。",
		"ハナさん、美咲さんからご伝言です。金曜の通院は、朝10時にお迎えに来るそうです。",
		"わかったよ。玄関で待ってるね。",
	}
	if got := utteranceTexts(t, ctx, ref); strings.Join(got, "\n") != strings.Join(wantLines, "\n") {
		t.Fatalf("会話 = %v", got)
	}
}

func assertReplyCard(t *testing.T, ctx context.Context, call *firestore.DocumentRef) {
	t.Helper()
	doc, err := call.Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	fields := doc.Data()
	if fields["message"] != "金曜の通院、10時に迎えに行くと伝えて" {
		t.Fatalf("伝えたいこと = %v", fields["message"])
	}
	const script = "「ハナさん、美咲さんからご伝言です。\n金曜の通院は、朝10時に\nお迎えに来るそうです。」"
	if fields["script"] != script {
		t.Fatalf("通話内容 = %v", fields["script"])
	}
	summary := nested(t, fields["summary"])
	if summary["told"] != "金曜の通院は、朝10時にお迎えに来る" {
		t.Fatalf("伝えたこと = %v", summary["told"])
	}
	reply := nested(t, summary["reply"])
	const want = "わかったよ。玄関で待ってるね。"
	if reply["text"] != want {
		t.Fatalf("返答 = %v", reply["text"])
	}
	utterances, err := call.Collection("utterances").Documents(ctx).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	for _, utterance := range utterances {
		data := utterance.Data()
		if data["speaker"] != protocol.SpeakerWatched || data["text"] != want {
			continue
		}
		if asInt(data["offsetMs"]) != asInt(reply["offsetMs"]) {
			t.Fatalf("返答の時刻 = %v, 発話 = %v", reply["offsetMs"], data["offsetMs"])
		}
		return
	}
	t.Fatalf("返答が見守る方の発話にない")
}

func utteranceTexts(t *testing.T, ctx context.Context, call *firestore.DocumentRef) []string {
	t.Helper()
	docs, err := call.Collection("utterances").Documents(ctx).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	lines := make([]string, len(docs))
	for _, doc := range docs {
		index := asInt(doc.Data()["index"])
		if index < 0 || int(index) >= len(lines) {
			t.Fatalf("発話の番号 = %d, 件数 = %d", index, len(docs))
		}
		text, _ := doc.Data()["text"].(string)
		lines[index] = text
	}
	return lines
}

func openEmulator(t *testing.T) (*firestore.Client, *auth.Client) {
	t.Helper()
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" || os.Getenv("FIREBASE_AUTH_EMULATOR_HOST") == "" {
		t.Fatal(firebasetest.Hint)
	}
	ctx := t.Context()
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: seedProject})
	if err != nil {
		t.Fatal(err)
	}
	store, err := app.Firestore(ctx)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	accounts, err := app.Auth(ctx)
	if err != nil {
		t.Fatal(err)
	}
	return store, accounts
}

func deletePersonBookings(t *testing.T, ctx context.Context, person *firestore.DocumentRef) error {
	t.Helper()
	docs, err := person.Collection("bookings").Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	for _, doc := range docs {
		if _, err := doc.Ref.Delete(ctx); err != nil {
			return err
		}
	}
	return nil
}

func signInToken(t *testing.T, email, password string) string {
	t.Helper()
	body, err := json.Marshal(map[string]any{
		"email": email, "password": password, "returnSecureToken": true,
		"targetProjectId": seedProject,
	})
	if err != nil {
		t.Fatal(err)
	}
	url := "http://" + os.Getenv("FIREBASE_AUTH_EMULATOR_HOST") + "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator"
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer owner")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("ログイン = %d", resp.StatusCode)
	}
	var parsed struct {
		IDToken string `json:"idToken"`
	}
	if json.Unmarshal(data, &parsed) != nil || parsed.IDToken == "" {
		t.Fatal("ログインのトークンが無かった")
	}
	return parsed.IDToken
}

func editSeedBooking(t *testing.T, backend, token, id string, at time.Time, message, script string) {
	t.Helper()
	body, err := json.Marshal(protocol.BookingBody{At: at, Message: message, Script: script})
	if err != nil {
		t.Fatal(err)
	}
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, backend+protocol.BookingPath+"/"+id, bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("直す = %d %s", resp.StatusCode, data)
	}
}

// dialSeedPhone は、鍵のある電話機を登録して person に結び、その ID と鍵でつなぐ。
// 合言葉は登録だけに使う。つなぐときに見守る方は名乗らない。
// 同じ見守る方に前の電話機が残っていると、電話の届く先が決まらないので、先に外す。
func dialSeedPhone(t *testing.T, store *firestore.Client, backend, person string) *websocket.Conn {
	t.Helper()
	id := seedPhoneID(t)
	const key = "dial-key"
	releaseSeedPhones(t, store, person)
	status, body := registerSeedPhone(t, backend, id, key)
	if status != http.StatusCreated && status != http.StatusOK {
		t.Fatalf("登録 = %d, want 201 か 200: %s", status, body)
	}
	if _, err := store.Collection("phones").Doc(id).Update(t.Context(), []firestore.Update{
		{Path: "watchedPersonId", Value: person},
	}); err != nil {
		t.Fatal(err)
	}
	return dialSeedPhoneKey(t, backend, id, key)
}

func seedPhoneID(t *testing.T) string {
	t.Helper()
	var nonce [6]byte
	if _, err := rand.Read(nonce[:]); err != nil {
		t.Fatal(err)
	}
	return "phone-" + hex.EncodeToString(nonce[:])
}

func releaseSeedPhones(t *testing.T, store *firestore.Client, person string) {
	t.Helper()
	docs, err := store.Collection("phones").Where("watchedPersonId", "==", person).Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	for _, doc := range docs {
		if _, err := doc.Ref.Update(t.Context(), []firestore.Update{
			{Path: "watchedPersonId", Value: ""},
		}); err != nil {
			t.Fatal(err)
		}
	}
}

func registerSeedPhone(t *testing.T, backend, id, key string) (int, []byte) {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, backend+protocol.PhoneRegisterPath, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set(protocol.PhoneSecretHeader, protocol.DevPhoneSecret)
	req.Header.Set(protocol.PhoneIDHeader, id)
	req.Header.Set(protocol.PhoneKeyHeader, key)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, body
}

func dialSeedPhoneKey(t *testing.T, backend, id, key string) *websocket.Conn {
	t.Helper()
	u, err := url.Parse(backend)
	if err != nil {
		t.Fatal(err)
	}
	u.Scheme = "ws"
	u.Path = protocol.PhonePath
	header := http.Header{}
	header.Set(protocol.PhoneIDHeader, id)
	header.Set(protocol.PhoneKeyHeader, key)
	conn, _, err := websocket.Dial(t.Context(), u.String(), &websocket.DialOptions{HTTPHeader: header})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.CloseNow() })
	return conn
}

func readSeedPhoneCalls(conn *websocket.Conn) <-chan protocol.PhoneMessage {
	calls := make(chan protocol.PhoneMessage, 1)
	go func() {
		for {
			_, data, err := conn.Read(context.Background())
			if err != nil {
				return
			}
			var msg protocol.PhoneMessage
			if json.Unmarshal(data, &msg) != nil || msg.Type != protocol.PhoneTypeCall {
				continue
			}
			calls <- msg
		}
	}()
	return calls
}

func waitSeedConnected(t *testing.T, handler *server.Handler, personID string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for !handler.Connected(personID) {
		if time.Now().After(deadline) {
			t.Fatal("電話機がつながらなかった")
		}
		time.Sleep(time.Millisecond)
	}
}

func waitSeedDeadline(t *testing.T, clk *clocktest.Clock, deadline time.Time) {
	t.Helper()
	done := make(chan struct{})
	go func() {
		clk.WaitForDeadline(deadline)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("予約の時刻のタイマーができなかった")
	}
}

func receiveSeedCall(t *testing.T, calls <-chan protocol.PhoneMessage) protocol.PhoneMessage {
	t.Helper()
	select {
	case got := <-calls:
		return got
	case <-time.After(2 * time.Second):
		t.Fatal("電話機に電話が来なかった")
	}
	return protocol.PhoneMessage{}
}

func callScript(t *testing.T, ctx context.Context, person *firestore.DocumentRef, callID string) string {
	t.Helper()
	doc, err := person.Collection("calls").Doc(callID).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	script, _ := doc.Data()["script"].(string)
	return script
}

func signInStatus(t *testing.T, email, password string) int {
	t.Helper()
	// エミュレーターの API キーは、起動したプロジェクト(demo-kazokuai)にだけ届く。
	// 審査員は seedProject にいるので、そのプロジェクトを指定できる owner でログインする。
	body, err := json.Marshal(map[string]any{
		"email": email, "password": password, "returnSecureToken": true,
		"targetProjectId": seedProject,
	})
	if err != nil {
		t.Fatal(err)
	}
	url := "http://" + os.Getenv("FIREBASE_AUTH_EMULATOR_HOST") + "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator"
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer owner")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode
}

func nested(t *testing.T, value any) map[string]any {
	t.Helper()
	item, ok := value.(map[string]any)
	if !ok {
		t.Fatalf("map ではない: %#v", value)
	}
	return item
}

func asInt(value any) int64 {
	switch n := value.(type) {
	case int64:
		return n
	case int:
		return int64(n)
	case float64:
		return int64(n)
	default:
		return -1
	}
}
