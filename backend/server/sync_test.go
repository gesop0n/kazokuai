package server_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/clock/clocktest"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// syncPhoneKey は、このファイルのテストが電話機を登録するときの鍵である。
const syncPhoneKey = "alpha-key"

func TestSyncPrep(t *testing.T) {
	when := time.Date(2026, 11, 10, 9, 0, 0, 0, time.UTC)

	t.Run("開いている同期の準備はやり直しになり、10 分で切れる", func(t *testing.T) {
		srv, clk := newSyncServer(t, when)
		family := signUp(t)

		status, expires, code := postPrepAt(t, srv.URL, protocol.SyncPreparePath, family.IDToken)
		if status != http.StatusCreated || code != "" {
			t.Fatalf("始め = %d %s, want 201", status, code)
		}
		if !expires.Equal(when.Add(10 * time.Minute)) {
			t.Fatalf("期限 = %v, want %v", expires, when.Add(10*time.Minute))
		}

		status, again, code := postPrepAt(t, srv.URL, protocol.SyncPreparePath, family.IDToken)
		if status != http.StatusOK || code != "" || !again.Equal(expires) {
			t.Fatalf("すぐのやり直し = %d %s %v, want 200 で同じ期限", status, code, again)
		}

		clk.Advance(9 * time.Minute)
		status, still, code := postPrepAt(t, srv.URL, protocol.SyncPreparePath, family.IDToken)
		if status != http.StatusOK || code != "" || !still.Equal(expires) {
			t.Fatalf("9 分後 = %d %s %v, want 200 で同じ期限", status, code, still)
		}

		clk.Advance(time.Minute)
		status, fresh, code := postPrepAt(t, srv.URL, protocol.SyncPreparePath, family.IDToken)
		if status != http.StatusCreated || code != "" {
			t.Fatalf("10 分後 = %d %s, want 201", status, code)
		}
		if !fresh.Equal(when.Add(20 * time.Minute)) {
			t.Fatalf("新しい期限 = %v, want %v", fresh, when.Add(20*time.Minute))
		}
	})

	t.Run("1 時間に 5 回までで、開いているものは回数に入らない", func(t *testing.T) {
		srv, clk := newSyncServer(t, when)
		family := signUp(t)

		for i := range 5 {
			status, expires, code := postPrepAt(t, srv.URL, protocol.SyncPreparePath, family.IDToken)
			if status != http.StatusCreated || code != "" {
				t.Fatalf("%d 回目 = %d %s, want 201", i+1, status, code)
			}
			want := when.Add(time.Duration(i)*10*time.Minute + 10*time.Minute)
			if !expires.Equal(want) {
				t.Fatalf("%d 回目の期限 = %v, want %v", i+1, expires, want)
			}
			if i == 4 {
				status, again, code := postPrepAt(t, srv.URL, protocol.SyncPreparePath, family.IDToken)
				if status != http.StatusOK || code != "" || !again.Equal(expires) {
					t.Fatalf("5 回目のあいだのやり直し = %d %s %v, want 200 で同じ期限", status, code, again)
				}
			}
			clk.Advance(10 * time.Minute)
		}

		status, _, code := postPrepAt(t, srv.URL, protocol.SyncPreparePath, family.IDToken)
		if status != http.StatusTooManyRequests || code != protocol.SyncPrepLimited {
			t.Fatalf("6 回目 = %d %s, want 429 %s", status, code, protocol.SyncPrepLimited)
		}

		clk.Advance(10 * time.Minute)
		status, _, code = postPrepAt(t, srv.URL, protocol.SyncPreparePath, family.IDToken)
		if status != http.StatusCreated || code != "" {
			t.Fatalf("1 時間後 = %d %s, want 201", status, code)
		}
	})

	t.Run("ID トークンが無いと断る", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		resp := postJSON(t, srv.URL, protocol.SyncPreparePath, "", "")
		if resp.status != http.StatusUnauthorized {
			t.Fatalf("ステータス = %d, want 401: %s", resp.status, resp.body)
		}
	})

	t.Run("アプリの道は /api の下でも始められる", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		family := signUp(t)
		status, _, code := postPrepAt(t, srv.URL, "/api"+protocol.SyncPreparePath, family.IDToken)
		if status != http.StatusCreated || code != "" {
			t.Fatalf("始め = %d %s, want 201", status, code)
		}
	})
}

func TestSyncCode(t *testing.T) {
	when := time.Date(2026, 11, 10, 9, 0, 0, 0, time.UTC)

	t.Run("同期していない電話機は、いつでも同じ認証コードをもらい、10 分で新しいものになる", func(t *testing.T) {
		srv, clk := newSyncServer(t, when)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)

		code := syncCodeOf(t, askSyncCode(t, srv.URL, id))
		clk.Advance(9 * time.Minute)
		if again := syncCodeOf(t, askSyncCode(t, srv.URL, id)); again != code {
			t.Fatal("10 分経たないのに認証コードが変わった")
		}
		clk.Advance(time.Minute)
		if fresh := syncCodeOf(t, askSyncCode(t, srv.URL, id)); fresh == code {
			t.Fatal("10 分経っても認証コードが同じ")
		}
	})

	t.Run("知らない電話機と、鍵が違う電話機と、合言葉だけの頼みは断る", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		id := testPhoneID(t)

		unknown := callPhone(t, srv.URL, http.MethodPost, protocol.PhoneCodePath, id, syncPhoneKey, "")
		if unknown.status != http.StatusNotFound || !strings.Contains(string(unknown.body), protocol.PhoneAnswerUnknownPhone) {
			t.Fatalf("知らない電話機 = %d %s, want 404 %s", unknown.status, unknown.body, protocol.PhoneAnswerUnknownPhone)
		}

		registerKeyedPhone(t, srv.URL, id)
		badKey := callPhone(t, srv.URL, http.MethodPost, protocol.PhoneCodePath, id, "wrong-key", "")
		if badKey.status != http.StatusUnauthorized || !strings.Contains(string(badKey.body), protocol.PhoneAnswerBadKey) {
			t.Fatalf("鍵が違う = %d %s, want 401 %s", badKey.status, badKey.body, protocol.PhoneAnswerBadKey)
		}

		legacy := askSyncCodeWithSecret(t, srv.URL)
		if legacy.status != http.StatusBadRequest || !strings.Contains(string(legacy.body), "電話機の ID と鍵を入れてください") {
			t.Fatalf("合言葉だけ = %d %s, want 400", legacy.status, legacy.body)
		}
	})

	t.Run("認証コードの道は /api の下にない", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)
		resp := callPhone(t, srv.URL, http.MethodPost, "/api"+protocol.PhoneCodePath, id, syncPhoneKey, "")
		if resp.status != http.StatusNotFound {
			t.Fatalf("ステータス = %d, want 404: %s", resp.status, resp.body)
		}
	})

	t.Run("同期済みの電話機は、その見守る方の家族が準備しているあいだだけ認証コードをもらう", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		owner := signUp(t)
		other := signUp(t)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)
		linkPhoneWithCode(t, srv.URL, owner.IDToken, id)

		status, _, code := postPrepAt(t, srv.URL, protocol.SyncPreparePath, other.IDToken)
		if status != http.StatusCreated || code != "" {
			t.Fatalf("ほかの家族の準備 = %d %s, want 201", status, code)
		}
		closed := askSyncCode(t, srv.URL, id)
		if closed.status != http.StatusConflict || !strings.Contains(string(closed.body), protocol.PhoneAnswerSyncClosed) {
			t.Fatalf("ほかの家族の準備中 = %d %s, want 409 %s", closed.status, closed.body, protocol.PhoneAnswerSyncClosed)
		}

		status, _, code = postPrepAt(t, srv.URL, protocol.SyncPreparePath, owner.IDToken)
		if status != http.StatusCreated || code != "" {
			t.Fatalf("家族の準備 = %d %s, want 201", status, code)
		}
		syncCodeOf(t, askSyncCode(t, srv.URL, id))
	})

	t.Run("電話が始まると、その電話機の認証コードは捨てる", func(t *testing.T) {
		srv, handler, _ := newSyncServerWith(t, when)
		family := signUp(t)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)
		personID := linkPhoneWithCode(t, srv.URL, family.IDToken, id)

		status, _, errCode := postPrepAt(t, srv.URL, protocol.SyncPreparePath, family.IDToken)
		if status != http.StatusCreated || errCode != "" {
			t.Fatalf("準備 = %d %s, want 201", status, errCode)
		}
		code := syncCodeOf(t, askSyncCode(t, srv.URL, id))

		missed := postJSON(t, srv.URL, protocol.StartCallPath, "Bearer "+family.IDToken, `{"message": "金曜の通院", "script": "ハナさん、美咲さんからです。"}`)
		if missed.status != http.StatusConflict || !strings.Contains(string(missed.body), protocol.PhoneNotConnected) {
			t.Fatalf("つながっていない今すぐ通話 = %d %s, want 409 %s", missed.status, missed.body, protocol.PhoneNotConnected)
		}
		if again := syncCodeOf(t, askSyncCode(t, srv.URL, id)); again != code {
			t.Fatal("届かなかった電話で認証コードが捨てられた")
		}

		conn := dialPhoneKey(t, srv.URL, id, syncPhoneKey, "")
		collectMessages(t, conn)
		waitConnected(t, handler, personID, true)
		startNow(t, srv.URL, protocol.StartCallPath, family.IDToken)
		if fresh := syncCodeOf(t, askSyncCode(t, srv.URL, id)); fresh == code {
			t.Fatal("電話が始まっても認証コードが同じ")
		}
	})
}

func TestSendSyncCode(t *testing.T) {
	when := time.Date(2026, 11, 10, 9, 0, 0, 0, time.UTC)

	t.Run("正しい認証コードで結び付き、/api からも送れる", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		family := signUp(t)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)

		status, _, errCode := postPrepAt(t, srv.URL, "/api"+protocol.SyncPreparePath, family.IDToken)
		if status != http.StatusCreated || errCode != "" {
			t.Fatalf("準備 = %d %s, want 201", status, errCode)
		}
		code := syncCodeOf(t, askSyncCode(t, srv.URL, id))
		resp := sendSyncCode(t, srv.URL, "/api"+protocol.SyncCodePath, family.IDToken, code)
		personID := linkedPersonID(t, resp)
		got := watchedPersonsOf(t, family.UID)
		if len(got) != 1 || got[0].Ref.ID != personID {
			t.Fatalf("見守る方 = %v, want %s の 1 人", ids(got), personID)
		}
	})

	t.Run("間違えても、正しいコードはまだ使える", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		family := signUp(t)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)
		prepareSync(t, srv.URL, family.IDToken)
		code := syncCodeOf(t, askSyncCode(t, srv.URL, id))

		wrong := sendSyncCode(t, srv.URL, protocol.SyncCodePath, family.IDToken, otherDigits(code))
		if wrong.status != http.StatusBadRequest || errorCode(t, wrong) != protocol.SyncCodeWrong {
			t.Fatalf("間違い = %d %s, want 400 %s", wrong.status, wrong.body, protocol.SyncCodeWrong)
		}
		linkedPersonID(t, sendSyncCode(t, srv.URL, protocol.SyncCodePath, family.IDToken, code))
	})

	t.Run("5 回目の間違いで同期の準備が終わり、コードは残る", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		family := signUp(t)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)
		prepareSync(t, srv.URL, family.IDToken)
		code := syncCodeOf(t, askSyncCode(t, srv.URL, id))
		wrong := otherDigits(code)

		for i := 1; i <= 4; i++ {
			resp := sendSyncCode(t, srv.URL, protocol.SyncCodePath, family.IDToken, wrong)
			if resp.status != http.StatusBadRequest || errorCode(t, resp) != protocol.SyncCodeWrong {
				t.Fatalf("%d 回目 = %d %s, want 400 %s", i, resp.status, resp.body, protocol.SyncCodeWrong)
			}
		}
		fifth := sendSyncCode(t, srv.URL, protocol.SyncCodePath, family.IDToken, wrong)
		if fifth.status != http.StatusConflict || errorCode(t, fifth) != protocol.SyncPrepEnded {
			t.Fatalf("5 回目 = %d %s, want 409 %s", fifth.status, fifth.body, protocol.SyncPrepEnded)
		}
		after := sendSyncCode(t, srv.URL, protocol.SyncCodePath, family.IDToken, code)
		if after.status != http.StatusConflict || errorCode(t, after) != protocol.SyncPrepEnded {
			t.Fatalf("終わったあとの正しいコード = %d %s, want 409 %s", after.status, after.body, protocol.SyncPrepEnded)
		}
		if got := watchedPersonsOf(t, family.UID); len(got) != 0 {
			t.Fatalf("見守る方 = %v, want いない", ids(got))
		}

		prepareSync(t, srv.URL, family.IDToken)
		linkedPersonID(t, sendSyncCode(t, srv.URL, protocol.SyncCodePath, family.IDToken, code))
	})

	t.Run("切れた同期の準備では、認証コードを送っても見守る方を作らない", func(t *testing.T) {
		srv, clk := newSyncServer(t, when)
		family := signUp(t)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)
		prepareSync(t, srv.URL, family.IDToken)
		code := syncCodeOf(t, askSyncCode(t, srv.URL, id))

		clk.Advance(10 * time.Minute)
		resp := sendSyncCode(t, srv.URL, protocol.SyncCodePath, family.IDToken, code)
		if resp.status != http.StatusConflict || errorCode(t, resp) != protocol.SyncPrepEnded {
			t.Fatalf("切れた準備 = %d %s, want 409 %s", resp.status, resp.body, protocol.SyncPrepEnded)
		}
		if got := watchedPersonsOf(t, family.UID); len(got) != 0 {
			t.Fatalf("見守る方 = %v, want いない", ids(got))
		}
	})

	t.Run("ほかの家族が同期済みの電話機のコードを送ると間違いになり、持ち主はまだ使える", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		owner := signUp(t)
		other := signUp(t)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)
		personID := linkPhoneWithCode(t, srv.URL, owner.IDToken, id)

		prepareSync(t, srv.URL, owner.IDToken)
		code := syncCodeOf(t, askSyncCode(t, srv.URL, id))
		prepareSync(t, srv.URL, other.IDToken)

		wrong := sendSyncCode(t, srv.URL, protocol.SyncCodePath, other.IDToken, code)
		if wrong.status != http.StatusBadRequest || errorCode(t, wrong) != protocol.SyncCodeWrong {
			t.Fatalf("ほかの家族 = %d %s, want 400 %s", wrong.status, wrong.body, protocol.SyncCodeWrong)
		}
		if phoneDoc(t, id)["watchedPersonId"] != personID {
			t.Fatalf("電話機の見守る方 = %v, want %s", phoneDoc(t, id)["watchedPersonId"], personID)
		}

		resp := sendSyncCode(t, srv.URL, protocol.SyncCodePath, owner.IDToken, code)
		if got := linkedPersonID(t, resp); got != personID {
			t.Fatalf("持ち主の結び付き = %s, want %s", got, personID)
		}
		if phoneDoc(t, id)["watchedPersonId"] != personID {
			t.Fatalf("電話機の見守る方 = %v, want %s", phoneDoc(t, id)["watchedPersonId"], personID)
		}
		if got := watchedPersonsOf(t, other.UID); len(got) != 0 {
			t.Fatalf("ほかの家族の見守る方 = %v, want いない", ids(got))
		}
	})
}

func TestLinkPhone(t *testing.T) {
	when := time.Date(2026, 11, 10, 9, 0, 0, 0, time.UTC)

	t.Run("同期で作った名前のない見守る方に、登録が名前を入れる", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		family := signUp(t)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)
		registeredAt, _ := phoneDoc(t, id)["registeredAt"].(time.Time)

		personID := linkPhoneWithCode(t, srv.URL, family.IDToken, id)
		got := watchedPersonsOf(t, family.UID)
		if len(got) != 1 || got[0].Ref.ID != personID {
			t.Fatalf("見守る方 = %v, want %s の 1 人", ids(got), personID)
		}
		data := got[0].Data()
		if data["name"] != "" || data["callName"] != "" {
			t.Fatalf("名前 = %v、呼び方 = %v, want どちらも空", data["name"], data["callName"])
		}
		if data["phoneId"] != id {
			t.Fatalf("電話機 = %v, want %s", data["phoneId"], id)
		}
		syncedAt, _ := data["syncedAt"].(time.Time)
		if !syncedAt.Equal(when) {
			t.Fatalf("結び付けた時刻 = %v, want %v", data["syncedAt"], when)
		}
		phone := phoneDoc(t, id)
		if phone["watchedPersonId"] != personID {
			t.Fatalf("電話機の見守る方 = %v, want %s", phone["watchedPersonId"], personID)
		}
		phoneSynced, _ := phone["syncedAt"].(time.Time)
		if !phoneSynced.Equal(when) {
			t.Fatalf("電話機を結び付けた時刻 = %v, want %v", phone["syncedAt"], when)
		}
		phoneRegistered, _ := phone["registeredAt"].(time.Time)
		if !phoneRegistered.Equal(registeredAt) {
			t.Fatalf("登録した時刻 = %v, want %v", phone["registeredAt"], registeredAt)
		}

		filled := register(t, srv.URL, "Bearer "+family.IDToken, `{"name": "山田花子", "callName": "ハナさん"}`)
		if filled.status != http.StatusCreated {
			t.Fatalf("登録 = %d, want 201: %s", filled.status, filled.body)
		}
		var created struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(filled.body, &created); err != nil || created.ID != personID {
			t.Fatalf("登録が返した ID = %s, want %s", filled.body, personID)
		}
		data = watchedPersonsOf(t, family.UID)[0].Data()
		if data["name"] != "山田花子" || data["callName"] != "ハナさん" || data["phoneId"] != id {
			t.Fatalf("登録のあと = %v", data)
		}

		second := register(t, srv.URL, "Bearer "+family.IDToken, `{"name": "山田太郎", "callName": "タロウさん"}`)
		if second.status != http.StatusConflict {
			t.Fatalf("2 人目 = %d, want 409: %s", second.status, second.body)
		}
		if got := watchedPersonsOf(t, family.UID); len(got) != 1 || got[0].Data()["name"] != "山田花子" {
			t.Fatalf("見守る方 = %v, want 山田花子さんだけ", names(got))
		}
	})

	t.Run("名前のある見守る方に電話機が付く", func(t *testing.T) {
		srv, _ := newSyncServer(t, when)
		family := signUp(t)
		created := register(t, srv.URL, "Bearer "+family.IDToken, `{"name": "山田花子", "callName": "ハナさん"}`)
		if created.status != http.StatusCreated {
			t.Fatalf("登録 = %d, want 201: %s", created.status, created.body)
		}
		var person struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(created.body, &person); err != nil || person.ID == "" {
			t.Fatalf("登録の本文 = %s", created.body)
		}
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)

		got := linkPhoneWithCode(t, srv.URL, family.IDToken, id)
		if got != person.ID {
			t.Fatalf("結び付けた見守る方 = %s, want %s", got, person.ID)
		}
		docs := watchedPersonsOf(t, family.UID)
		if len(docs) != 1 || docs[0].Data()["name"] != "山田花子" || docs[0].Data()["phoneId"] != id {
			t.Fatalf("見守る方 = %v", names(docs))
		}
	})

	t.Run("先の電話機は同期していない電話機に戻り、あとの電話機が付く", func(t *testing.T) {
		srv, clk := newSyncServer(t, when)
		family := signUp(t)
		firstID := testPhoneID(t) + "-a"
		secondID := testPhoneID(t) + "-b"
		registerKeyedPhone(t, srv.URL, firstID)
		registerKeyedPhone(t, srv.URL, secondID)

		personID := linkPhoneWithCode(t, srv.URL, family.IDToken, firstID)
		clk.Advance(time.Minute)
		prepareSync(t, srv.URL, family.IDToken)
		secondCode := syncCodeOf(t, askSyncCode(t, srv.URL, secondID))
		resp := sendSyncCode(t, srv.URL, protocol.SyncCodePath, family.IDToken, secondCode)
		if got := linkedPersonID(t, resp); got != personID {
			t.Fatalf("結び付けた見守る方 = %s, want %s", got, personID)
		}

		docs := watchedPersonsOf(t, family.UID)
		if len(docs) != 1 {
			t.Fatalf("見守る方 = %d 人, want 1", len(docs))
		}
		data := docs[0].Data()
		if data["phoneId"] != secondID {
			t.Fatalf("電話機 = %v, want %s", data["phoneId"], secondID)
		}
		syncedAt, _ := data["syncedAt"].(time.Time)
		if !syncedAt.Equal(when.Add(time.Minute)) {
			t.Fatalf("結び付けた時刻 = %v, want %v", data["syncedAt"], when.Add(time.Minute))
		}
		if phoneDoc(t, firstID)["watchedPersonId"] != "" {
			t.Fatalf("先の電話機 = %v, want 空", phoneDoc(t, firstID)["watchedPersonId"])
		}
		if phoneDoc(t, secondID)["watchedPersonId"] != personID {
			t.Fatalf("あとの電話機 = %v, want %s", phoneDoc(t, secondID)["watchedPersonId"], personID)
		}
	})

	t.Run("同じ電話機をもう一度結び付けても、時刻も知らせも変わらない", func(t *testing.T) {
		srv, handler, clk := newSyncServerWith(t, when)
		family := signUp(t)
		id := testPhoneID(t)
		registerKeyedPhone(t, srv.URL, id)
		personID := linkPhoneWithCode(t, srv.URL, family.IDToken, id)

		conn := dialPhoneKey(t, srv.URL, id, syncPhoneKey, "")
		msgs := collectMessages(t, conn)
		awaitMessage(t, msgs, protocol.PhoneTypeSynced)
		waitConnected(t, handler, personID, true)

		clk.Advance(time.Minute)
		prepareSync(t, srv.URL, family.IDToken)
		code := syncCodeOf(t, askSyncCode(t, srv.URL, id))
		resp := sendSyncCode(t, srv.URL, protocol.SyncCodePath, family.IDToken, code)
		if got := linkedPersonID(t, resp); got != personID {
			t.Fatalf("結び付けた見守る方 = %s, want %s", got, personID)
		}

		data := watchedPersonsOf(t, family.UID)[0].Data()
		syncedAt, _ := data["syncedAt"].(time.Time)
		if data["phoneId"] != id || !syncedAt.Equal(when) {
			t.Fatalf("見守る方の結び付き = %v %v, want %s %v", data["phoneId"], data["syncedAt"], id, when)
		}
		phoneSynced, _ := phoneDoc(t, id)["syncedAt"].(time.Time)
		if !phoneSynced.Equal(when) {
			t.Fatalf("電話機を結び付けた時刻 = %v, want %v", phoneDoc(t, id)["syncedAt"], when)
		}
		awaitNoMessage(t, msgs)
	})
}

func TestSyncNotifiesPhone(t *testing.T) {
	when := time.Date(2026, 11, 10, 9, 0, 0, 0, time.UTC)
	srv, handler, _ := newSyncServerWith(t, when)
	family := signUp(t)
	firstID := testPhoneID(t) + "-a"
	secondID := testPhoneID(t) + "-b"
	registerKeyedPhone(t, srv.URL, firstID)
	registerKeyedPhone(t, srv.URL, secondID)

	personID := linkPhoneWithCode(t, srv.URL, family.IDToken, firstID)
	first := dialPhoneKey(t, srv.URL, firstID, syncPhoneKey, "")
	firstMsgs := collectMessages(t, first)
	awaitMessage(t, firstMsgs, protocol.PhoneTypeSynced)
	waitConnected(t, handler, personID, true)
	callID := startNow(t, srv.URL, protocol.StartCallPath, family.IDToken)
	if callState(t, personID, callID) != protocol.StateRinging {
		t.Fatalf("状態 = %s, want %s", callState(t, personID, callID), protocol.StateRinging)
	}

	second := dialPhoneKey(t, srv.URL, secondID, syncPhoneKey, "")
	secondMsgs := collectMessages(t, second)
	awaitMessage(t, secondMsgs, protocol.PhoneTypeNotSynced)

	prepareSync(t, srv.URL, family.IDToken)
	code := syncCodeOf(t, askSyncCode(t, srv.URL, secondID))
	resp := sendSyncCode(t, srv.URL, protocol.SyncCodePath, family.IDToken, code)
	if got := linkedPersonID(t, resp); got != personID {
		t.Fatalf("結び付けた見守る方 = %s, want %s", got, personID)
	}
	awaitMessage(t, firstMsgs, protocol.PhoneTypeNotSynced)
	awaitMessage(t, secondMsgs, protocol.PhoneTypeSynced)

	if callState(t, personID, callID) != protocol.StateFailed {
		t.Fatalf("状態 = %s, want %s", callState(t, personID, callID), protocol.StateFailed)
	}
	sendPhoneState(t, first, callID, protocol.StateEnded)
	stayCallState(t, personID, callID, protocol.StateFailed, 200*time.Millisecond)

	data := watchedPersonsOf(t, family.UID)[0].Data()
	if data["phoneId"] != secondID {
		t.Fatalf("電話機 = %v, want %s", data["phoneId"], secondID)
	}
	if phoneDoc(t, firstID)["watchedPersonId"] != "" {
		t.Fatalf("先の電話機 = %v, want 空", phoneDoc(t, firstID)["watchedPersonId"])
	}
	if phoneDoc(t, secondID)["watchedPersonId"] != personID {
		t.Fatalf("あとの電話機 = %v, want %s", phoneDoc(t, secondID)["watchedPersonId"], personID)
	}
}

func newSyncServer(t *testing.T, when time.Time) (*httptest.Server, *clocktest.Clock) {
	t.Helper()
	srv, _, clk := newSyncServerWith(t, when)
	return srv, clk
}

func newSyncServerWith(t *testing.T, when time.Time) (*httptest.Server, *server.Handler, *clocktest.Clock) {
	t.Helper()
	clk := clocktest.New(when)
	srv, handler := newAuthServer(t, clk)
	return srv, handler, clk
}

func registerKeyedPhone(t *testing.T, backend, id string) {
	t.Helper()
	resp := registerPhone(t, backend, protocol.DevPhoneSecret, id, syncPhoneKey)
	if resp.status != http.StatusCreated {
		t.Fatalf("電話機の登録 = %d, want 201: %s", resp.status, resp.body)
	}
}

func postPrepAt(t *testing.T, backend, path, token string) (status int, expires time.Time, code string) {
	t.Helper()
	resp := postJSON(t, backend, path, "Bearer "+token, "")
	var body struct {
		ExpiresAt time.Time `json:"expiresAt"`
		Error     string    `json:"error"`
	}
	_ = json.Unmarshal(resp.body, &body)
	return resp.status, body.ExpiresAt, body.Error
}

func prepareSync(t *testing.T, backend, token string) {
	t.Helper()
	status, _, code := postPrepAt(t, backend, protocol.SyncPreparePath, token)
	if status != http.StatusCreated || code != "" {
		t.Fatalf("同期の準備 = %d %s, want 201", status, code)
	}
}

func askSyncCode(t *testing.T, backend, id string) response {
	t.Helper()
	return callPhone(t, backend, http.MethodPost, protocol.PhoneCodePath, id, syncPhoneKey, "")
}

func askSyncCodeWithSecret(t *testing.T, backend string) response {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, backend+protocol.PhoneCodePath, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set(protocol.PhoneSecretHeader, protocol.DevPhoneSecret)
	return doRequest(t, req)
}

func syncCodeOf(t *testing.T, resp response) string {
	t.Helper()
	if resp.status != http.StatusOK {
		t.Fatalf("認証コード = %d %s, want 200", resp.status, resp.body)
	}
	var body struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(resp.body, &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Code) != 6 {
		t.Fatalf("認証コードの桁 = %d, want 6", len(body.Code))
	}
	for _, r := range body.Code {
		if r < '0' || r > '9' {
			t.Fatal("認証コードに数字以外がある")
		}
	}
	return body.Code
}

func otherDigits(code string) string {
	flipped := []byte(code)
	if flipped[0] == '0' {
		flipped[0] = '1'
	} else {
		flipped[0] = '0'
	}
	return string(flipped)
}

func sendSyncCode(t *testing.T, backend, path, token, code string) response {
	t.Helper()
	body, err := json.Marshal(map[string]string{"code": code})
	if err != nil {
		t.Fatal(err)
	}
	return postJSON(t, backend, path, "Bearer "+token, string(body))
}

func errorCode(t *testing.T, resp response) string {
	t.Helper()
	var body struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(resp.body, &body); err != nil {
		t.Fatalf("本文を読めなかった: %s", resp.body)
	}
	return body.Error
}

func linkedPersonID(t *testing.T, resp response) string {
	t.Helper()
	if resp.status != http.StatusOK {
		t.Fatalf("結び付き = %d, want 200: %s", resp.status, resp.body)
	}
	var body struct {
		WatchedPersonID string `json:"watchedPersonId"`
	}
	if err := json.Unmarshal(resp.body, &body); err != nil || body.WatchedPersonID == "" {
		t.Fatalf("結び付きの本文 = %s", resp.body)
	}
	return body.WatchedPersonID
}

func linkPhoneWithCode(t *testing.T, backend, token, phoneID string) string {
	t.Helper()
	prepareSync(t, backend, token)
	code := syncCodeOf(t, askSyncCode(t, backend, phoneID))
	return linkedPersonID(t, sendSyncCode(t, backend, protocol.SyncCodePath, token, code))
}

func collectMessages(t *testing.T, conn *websocket.Conn) <-chan protocol.PhoneMessage {
	t.Helper()
	out := make(chan protocol.PhoneMessage, 16)
	go func() {
		defer close(out)
		for {
			_, data, err := conn.Read(context.Background())
			if err != nil {
				return
			}
			var msg protocol.PhoneMessage
			if json.Unmarshal(data, &msg) != nil {
				continue
			}
			out <- msg
		}
	}()
	return out
}

func awaitMessage(t *testing.T, msgs <-chan protocol.PhoneMessage, kind string) {
	t.Helper()
	timer := time.NewTimer(2 * time.Second)
	defer timer.Stop()
	for {
		select {
		case msg, ok := <-msgs:
			if !ok {
				t.Fatalf("接続が切れた。%s を待っていた", kind)
			}
			if msg.Type == kind {
				return
			}
		case <-timer.C:
			t.Fatalf("%s が届かなかった", kind)
		}
	}
}

func awaitNoMessage(t *testing.T, msgs <-chan protocol.PhoneMessage) {
	t.Helper()
	timer := time.NewTimer(200 * time.Millisecond)
	defer timer.Stop()
	select {
	case msg, ok := <-msgs:
		if !ok {
			t.Fatal("接続が切れた")
		}
		t.Fatalf("知らせが届いた: %s", msg.Type)
	case <-timer.C:
	}
}
