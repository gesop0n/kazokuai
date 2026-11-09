package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"

	"github.com/gesop0n/kazokuai/internal/firebasetest"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// 時刻は日本時間。アプリは端末の現地時間で出す。審査は日本である。
var tokyo = time.FixedZone("Asia/Tokyo", 9*60*60)

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

	other, err := firebasetest.SignUp(ctx)
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

	again := seedJudge(t, ctx, store, accounts, email, next, today)
	if again.WatchedPersonID != got.WatchedPersonID || again.UID != got.UID {
		t.Fatalf("戻したあとの ID = %+v, 最初 = %+v", again, got)
	}
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
		ProjectID:     "demo-kazokuai",
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
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: "demo-kazokuai"})
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

func signInStatus(t *testing.T, email, password string) int {
	t.Helper()
	body, err := json.Marshal(map[string]any{
		"email": email, "password": password, "returnSecureToken": true,
	})
	if err != nil {
		t.Fatal(err)
	}
	url := "http://" + os.Getenv("FIREBASE_AUTH_EMULATOR_HOST") + "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator"
	resp, err := http.Post(url, "application/json", bytes.NewReader(body))
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
