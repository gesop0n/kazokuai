package server_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/gesop0n/kazokuai/backend/server"
	"github.com/gesop0n/kazokuai/internal/clock/clocktest"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

// 予約のテストが使う今。既存のテストの 2026-01-02 とはずらしてある。
var bookingNow = time.Date(2026, 11, 10, 1, 0, 0, 0, time.UTC)

const (
	taskAudience = "https://backend.example"
	taskAccount  = "tasks@example.iam.gserviceaccount.com"
	taskToken    = "good-task-token"
	bookingMsg   = "金曜の通院"
	bookingWords = "ハナさん、美咲さんからです。"
)

func TestSaveBooking(t *testing.T) {
	t.Run("1 分より先なら保存し、伝えたいことと通話内容と番号を残す", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		at := bookingNow.Add(time.Hour)

		resp := postBooking(t, srv.URL, protocol.BookingPath, token, at, " 金曜の通院 ", "\tハナさん、美咲さんからです。 ")

		id := createdBooking(t, resp)
		data := bookingData(t, person, id)
		if data["message"] != bookingMsg || data["script"] != bookingWords {
			t.Fatalf("予約 = %v, want 空白を除いた伝えたいことと通話内容", data)
		}
		if data["number"] != int64(1) || data["called"] != false {
			t.Fatalf("番号とかけた印 = %v %v, want 1 と false", data["number"], data["called"])
		}
		got, _ := data["at"].(time.Time)
		if !got.Equal(at) {
			t.Fatalf("時刻 = %s, want %s", got, at)
		}
	})

	t.Run("/api の下でも保存する", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)

		resp := postBooking(t, srv.URL, "/api"+protocol.BookingPath, token, bookingNow.Add(2*time.Hour), bookingMsg, bookingWords)

		id := createdBooking(t, resp)
		if bookingData(t, person, id)["message"] != bookingMsg {
			t.Fatal("予約が残っていない")
		}
	})

	t.Run("ちょうど 1 分先は早すぎて、30 日先は保存でき、30 日より先は先すぎる", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)

		tooSoon := postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(time.Minute), bookingMsg, bookingWords)
		assertBookingError(t, tooSoon, http.StatusConflict, protocol.BookingTooSoon)

		far := postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(30*24*time.Hour), bookingMsg, bookingWords)
		if far.status != http.StatusCreated {
			t.Fatalf("30 日先 = %d %s, want 201", far.status, far.body)
		}

		tooFar := postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(30*24*time.Hour+time.Second), bookingMsg, bookingWords)
		assertBookingError(t, tooFar, http.StatusConflict, protocol.BookingTooFar)
		if n := len(bookingsOf(t, person)); n != 1 {
			t.Fatalf("残った予約 = %d, want 30 日先の 1 件", n)
		}
	})

	t.Run("前後 10 分以内の予約は断る。10 分を超えて離れていれば保存する", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		first := bookingNow.Add(time.Hour)
		if resp := postBooking(t, srv.URL, protocol.BookingPath, token, first, bookingMsg, bookingWords); resp.status != http.StatusCreated {
			t.Fatalf("1 件目 = %d %s", resp.status, resp.body)
		}

		closeBy := postBooking(t, srv.URL, protocol.BookingPath, token, first.Add(10*time.Minute), "近い", bookingWords)
		assertBookingError(t, closeBy, http.StatusConflict, protocol.BookingTooClose)

		apart := postBooking(t, srv.URL, protocol.BookingPath, token, first.Add(10*time.Minute+time.Second), "離れている", bookingWords)
		if apart.status != http.StatusCreated {
			t.Fatalf("10 分より離れた予約 = %d %s, want 201", apart.status, apart.body)
		}
	})

	t.Run("別の家族の予約が近くても保存できる", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		hanako, misaki := registerHanako(t, srv.URL)
		taro, kenta := registerPerson(t, srv.URL, "佐藤太郎", "タロウさん")
		forgetBookings(t, hanako)
		forgetBookings(t, taro)
		at := bookingNow.Add(time.Hour)
		if resp := postBooking(t, srv.URL, protocol.BookingPath, misaki, at, bookingMsg, bookingWords); resp.status != http.StatusCreated {
			t.Fatalf("花子さんの予約 = %d %s", resp.status, resp.body)
		}

		resp := postBooking(t, srv.URL, protocol.BookingPath, kenta, at.Add(time.Minute), "太郎さんへの伝言", "タロウさん、健太からです。")

		if resp.status != http.StatusCreated {
			t.Fatalf("別の家族の近い予約 = %d %s, want 201", resp.status, resp.body)
		}
		if n := len(bookingsOf(t, hanako)); n != 1 {
			t.Fatalf("花子さんの予約 = %d, want 1", n)
		}
	})

	t.Run("見守る方がいない家族と、ID トークンが無い頼みは断る", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		stranger := signUp(t)
		at := bookingNow.Add(time.Hour)

		noPerson := postBooking(t, srv.URL, protocol.BookingPath, stranger.IDToken, at, bookingMsg, bookingWords)
		if noPerson.status != http.StatusForbidden {
			t.Fatalf("見守る方がいない = %d %s, want 403", noPerson.status, noPerson.body)
		}
		noToken := postBooking(t, srv.URL, protocol.BookingPath, "", at, bookingMsg, bookingWords)
		if noToken.status != http.StatusUnauthorized {
			t.Fatalf("トークンがない = %d, want 401", noToken.status)
		}
	})
}

func TestEditBooking(t *testing.T) {
	t.Run("時刻と伝えたいことと通話内容を直し、番号が 1 つ増える。自分自身とはぶつからない", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(time.Hour), bookingMsg, bookingWords))
		at := bookingNow.Add(time.Hour + 5*time.Minute)

		resp := postBooking(t, srv.URL, "/api"+protocol.BookingPath+"/"+id, token, at, "薬の確認", "ハナさん、お薬は飲みましたか。")

		if resp.status != http.StatusOK {
			t.Fatalf("直す = %d %s, want 200", resp.status, resp.body)
		}
		data := bookingData(t, person, id)
		if data["message"] != "薬の確認" || data["script"] != "ハナさん、お薬は飲みましたか。" || data["number"] != int64(2) {
			t.Fatalf("直した予約 = %v", data)
		}
		got, _ := data["at"].(time.Time)
		if !got.Equal(at) {
			t.Fatalf("時刻 = %s, want %s", got, at)
		}
	})

	t.Run("ほかの予約の 10 分以内には直せない", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		firstAt := bookingNow.Add(time.Hour)
		first := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, firstAt, bookingMsg, bookingWords))
		secondAt := bookingNow.Add(2 * time.Hour)
		if resp := postBooking(t, srv.URL, protocol.BookingPath, token, secondAt, "夕方", bookingWords); resp.status != http.StatusCreated {
			t.Fatalf("2 件目 = %d %s", resp.status, resp.body)
		}

		resp := postBooking(t, srv.URL, protocol.BookingPath+"/"+first, token, secondAt.Add(5*time.Minute), bookingMsg, bookingWords)

		assertBookingError(t, resp, http.StatusConflict, protocol.BookingTooClose)
		got, _ := bookingData(t, person, first)["at"].(time.Time)
		if !got.Equal(firstAt) || bookingData(t, person, first)["number"] != int64(1) {
			t.Fatal("断ったのに予約が変わった")
		}
	})

	t.Run("無い予約は見つからない", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)

		resp := postBooking(t, srv.URL, protocol.BookingPath+"/missing", token, bookingNow.Add(time.Hour), bookingMsg, bookingWords)

		assertBookingError(t, resp, http.StatusNotFound, protocol.BookingNotFound)
		if n := len(bookingsOf(t, person)); n != 0 {
			t.Fatalf("予約 = %d, want 0", n)
		}
	})

	t.Run("かけたあとは直せない", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		at := bookingNow.Add(time.Hour)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, at, bookingMsg, bookingWords))
		if _, err := emulators.Firestore.Collection("watchedPersons").Doc(person).Collection("bookings").Doc(id).Update(t.Context(), []firestore.Update{{Path: "called", Value: true}}); err != nil {
			t.Fatal(err)
		}

		resp := postBooking(t, srv.URL, protocol.BookingPath+"/"+id, token, bookingNow.Add(2*time.Hour), "新しい伝言", bookingWords)

		assertBookingError(t, resp, http.StatusConflict, protocol.BookingAlreadyCalled)
		if bookingData(t, person, id)["message"] != bookingMsg {
			t.Fatal("かけたあとの予約が変わった")
		}
	})

	t.Run("別の家族の予約は直せない", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		hanako, misaki := registerHanako(t, srv.URL)
		taro, kenta := registerPerson(t, srv.URL, "佐藤太郎", "タロウさん")
		forgetBookings(t, hanako)
		forgetBookings(t, taro)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, misaki, bookingNow.Add(time.Hour), bookingMsg, bookingWords))

		resp := postBooking(t, srv.URL, protocol.BookingPath+"/"+id, kenta, bookingNow.Add(2*time.Hour), "書き換え", bookingWords)

		assertBookingError(t, resp, http.StatusNotFound, protocol.BookingNotFound)
		if bookingData(t, hanako, id)["message"] != bookingMsg {
			t.Fatal("別の家族が予約を直せた")
		}
		if n := len(bookingsOf(t, taro)); n != 0 {
			t.Fatalf("太郎さんの予約 = %d, want 0", n)
		}
	})
}

func TestBookingTaskAnswers(t *testing.T) {
	t.Run("電話機がつながっていなければやり直し、10 分後はつながらなかったにする", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv := newTaskServer(t, clk, allowTaskToken)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		at := bookingNow.Add(2 * time.Minute)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, at, bookingMsg, bookingWords))
		clk.Advance(2 * time.Minute)

		first := postTask(t, srv.URL, taskToken, person, id, 1)
		if first.status != http.StatusServiceUnavailable {
			t.Fatalf("つながっていない = %d %s, want 503", first.status, first.body)
		}
		if bookingData(t, person, id)["called"] != false || callCount(t, person) != 0 {
			t.Fatal("やり直す前に予約を終えた")
		}

		clk.Advance(9 * time.Minute)
		again := postTask(t, srv.URL, taskToken, person, id, 1)
		if again.status != http.StatusServiceUnavailable || bookingData(t, person, id)["called"] != false {
			t.Fatalf("9 分後 = %d、かけた = %v, want 503 と false", again.status, bookingData(t, person, id)["called"])
		}

		clk.Advance(time.Minute)
		gaveUp := postTask(t, srv.URL, taskToken, person, id, 1)
		if gaveUp.status != http.StatusOK {
			t.Fatalf("10 分後 = %d %s, want 200", gaveUp.status, gaveUp.body)
		}
		callID, call := onlyCall(t, person)
		if call["state"] != protocol.StateFailed || call["message"] != bookingMsg || call["script"] != bookingWords {
			t.Fatalf("電話 = %v, want つながらなかったと予約の伝えたいことと通話内容", call)
		}
		created, _ := call["createdAt"].(time.Time)
		if !created.Equal(at) {
			t.Fatalf("かけた時刻 = %s, want 予約した %s", created, at)
		}
		data := bookingData(t, person, id)
		if data["called"] != true || data["callId"] != callID {
			t.Fatalf("終えた予約 = %v", data)
		}
	})

	t.Run("電話の最中はやり直し、終わってからかける", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, handler := newTaskServerWith(t, clk, allowTaskToken)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		conn := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
		calls := readPhoneCalls(conn)
		waitConnected(t, handler, person, true)
		clk.WaitForTimers(1)
		at := bookingNow.Add(2 * time.Minute)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, at, bookingMsg, bookingWords))
		immediate := startNow(t, srv.URL, protocol.StartCallPath, token)
		receiveCall(t, calls, immediate)
		clk.Advance(2 * time.Minute)

		busy := postTask(t, srv.URL, taskToken, person, id, 1)
		if busy.status != http.StatusServiceUnavailable || bookingData(t, person, id)["called"] != false {
			t.Fatalf("電話の最中 = %d、かけた = %v, want 503 と false", busy.status, bookingData(t, person, id)["called"])
		}

		sendPhoneState(t, conn, immediate, protocol.StateEnded)
		waitCallState(t, person, immediate, protocol.StateEnded)
		placed := postTask(t, srv.URL, taskToken, person, id, 1)
		if placed.status != http.StatusOK {
			t.Fatalf("終わったあと = %d %s, want 200", placed.status, placed.body)
		}
		callID, _ := receiveCall(t, calls, "")
		if callState(t, person, callID) != protocol.StateRinging {
			t.Fatalf("予約の電話 = %s, want 呼び出し中", callState(t, person, callID))
		}
		if bookingData(t, person, id)["callId"] != callID || callData(t, person, callID)["script"] != bookingWords {
			t.Fatal("予約の電話が、予約の通話内容になっていない")
		}
	})

	t.Run("出なかったは今すぐ通話と同じく、電話の状態になる", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, handler := newTaskServerWith(t, clk, allowTaskToken)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		conn := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
		calls := readPhoneCalls(conn)
		waitConnected(t, handler, person, true)
		clk.WaitForTimers(1)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(2*time.Minute), bookingMsg, bookingWords))
		clk.Advance(2 * time.Minute)

		resp := postTask(t, srv.URL, taskToken, person, id, 1)
		if resp.status != http.StatusOK {
			t.Fatalf("予約の電話 = %d %s, want 200", resp.status, resp.body)
		}
		callID, _ := receiveCall(t, calls, "")
		sendPhoneState(t, conn, callID, protocol.StateMissed)
		waitCallState(t, person, callID, protocol.StateMissed)
	})

	t.Run("古い番号は何もしない", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, handler := newTaskServerWith(t, clk, allowTaskToken)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		conn := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
		calls := readPhoneCalls(conn)
		waitConnected(t, handler, person, true)
		clk.WaitForTimers(1)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(2*time.Minute), bookingMsg, bookingWords))
		edited := postBooking(t, srv.URL, protocol.BookingPath+"/"+id, token, bookingNow.Add(4*time.Minute), "薬の確認", "ハナさん、お薬は飲みましたか。")
		if edited.status != http.StatusOK {
			t.Fatalf("直す = %d %s", edited.status, edited.body)
		}
		clk.Advance(4 * time.Minute)

		old := postTask(t, srv.URL, taskToken, person, id, 1)
		if old.status != http.StatusOK || callCount(t, person) != 0 || bookingData(t, person, id)["called"] != false {
			t.Fatalf("古い番号 = %d、電話 = %d、かけた = %v", old.status, callCount(t, person), bookingData(t, person, id)["called"])
		}
		current := postTask(t, srv.URL, taskToken, person, id, 2)
		if current.status != http.StatusOK {
			t.Fatalf("今の番号 = %d %s, want 200", current.status, current.body)
		}
		callID, _ := receiveCall(t, calls, "")
		if callData(t, person, callID)["script"] != "ハナさん、お薬は飲みましたか。" {
			t.Fatalf("通話内容 = %v", callData(t, person, callID)["script"])
		}
	})

	t.Run("同じ番号が 2 回到いても、かけるのは 1 回", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, handler := newTaskServerWith(t, clk, allowTaskToken)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		conn := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
		calls := readPhoneCalls(conn)
		waitConnected(t, handler, person, true)
		clk.WaitForTimers(1)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(2*time.Minute), bookingMsg, bookingWords))
		clk.Advance(2 * time.Minute)

		start := make(chan struct{})
		var wg sync.WaitGroup
		got := make(chan response, 2)
		for range 2 {
			wg.Add(1)
			go func() {
				defer wg.Done()
				<-start
				got <- postTask(t, srv.URL, taskToken, person, id, 1)
			}()
		}
		close(start)
		wg.Wait()
		close(got)
		for resp := range got {
			if resp.status != http.StatusOK {
				t.Fatalf("2 回到着 = %d %s, want 200", resp.status, resp.body)
			}
		}
		if callCount(t, person) != 1 {
			t.Fatalf("電話 = %d, want 1", callCount(t, person))
		}
		receiveCall(t, calls, "")
		select {
		case extra := <-calls:
			t.Fatalf("2 回目の電話が来た: %s", extra.CallID)
		case <-time.After(200 * time.Millisecond):
		}
	})
}

func TestBookingTaskOIDC(t *testing.T) {
	t.Run("トークンが無いとかけない", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv := newTaskServer(t, clk, nil)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(time.Hour), bookingMsg, bookingWords))

		resp := postTask(t, srv.URL, "", person, id, 1)

		if resp.status != http.StatusUnauthorized || callCount(t, person) != 0 || bookingData(t, person, id)["called"] != false {
			t.Fatalf("トークンがない = %d %s", resp.status, resp.body)
		}
	})

	t.Run("違うトークンではかけない", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv := newTaskServer(t, clk, nil)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(time.Hour), bookingMsg, bookingWords))

		resp := postTask(t, srv.URL, "not-a-token", person, id, 1)

		if resp.status != http.StatusUnauthorized || bookingData(t, person, id)["called"] != false {
			t.Fatalf("違うトークン = %d %s", resp.status, resp.body)
		}
	})

	t.Run("サービスアカウントと違うメールではかけない", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv := newTaskServer(t, clk, func(context.Context, string, string) (string, error) {
			return "other@example.iam.gserviceaccount.com", nil
		})
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(time.Hour), bookingMsg, bookingWords))

		resp := postTask(t, srv.URL, taskToken, person, id, 1)

		if resp.status != http.StatusUnauthorized || bookingData(t, person, id)["called"] != false {
			t.Fatalf("違うアカウント = %d %s", resp.status, resp.body)
		}
	})

	t.Run("audience が空だと、検証が通ってもかけない", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		checked := false
		handler := server.New(server.Config{
			ProjectID:     "kazokuai-prod",
			PhoneSecret:   protocol.DevPhoneSecret,
			TasksAudience: "  ",
			TasksAccount:  taskAccount,
			CheckBookingOIDC: func(context.Context, string, string) (string, error) {
				checked = true
				return taskAccount, nil
			},
		}, emulators, nil, nil, clk)
		srv := httptest.NewServer(handler)
		t.Cleanup(func() {
			handler.Stop()
			srv.Close()
		})
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(time.Hour), bookingMsg, bookingWords))

		resp := postTask(t, srv.URL, taskToken, person, id, 1)

		if resp.status != http.StatusUnauthorized || checked || bookingData(t, person, id)["called"] != false {
			t.Fatalf("audience が空 = %d、検証を呼んだ = %v、かけた = %v", resp.status, checked, bookingData(t, person, id)["called"])
		}
	})

	t.Run("demo- のプロジェクトでは道を閉じる", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(time.Hour), bookingMsg, bookingWords))

		resp := postTask(t, srv.URL, taskToken, person, id, 1)
		if resp.status != http.StatusNotFound {
			t.Fatalf("demo- の道 = %d, want 404", resp.status)
		}
		api := postJSON(t, srv.URL, "/api"+protocol.BookingTaskPath, "Bearer "+taskToken, `{}`)
		if api.status != http.StatusNotFound {
			t.Fatalf("/api の下 = %d, want 404", api.status)
		}
		if bookingData(t, person, id)["called"] != false {
			t.Fatal("閉じた道が予約をかけた")
		}
	})
}

func TestEditedBookingIsScheduledAfterTheReadFails(t *testing.T) {
	clk := clocktest.New(bookingNow)
	srv, handler := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
	person, token := registerHanako(t, srv.URL)
	forgetBookings(t, person)
	conn := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
	calls := readPhoneCalls(conn)
	waitConnected(t, handler, person, true)
	clk.WaitForTimers(1)
	id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(3*time.Minute), bookingMsg, bookingWords))
	waitTimers(t, clk, 2)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	scheduled := make(chan struct{})
	reads := 0
	server.StubBookingScheduleRead(func(ctx context.Context, ref *firestore.DocumentRef) (*firestore.DocumentSnapshot, error) {
		reads++
		if reads == 1 {
			cancel()
			return nil, errors.New("一時的に読めない")
		}
		if ctx.Err() != nil {
			t.Errorf("やり直しが終わった context だった: %v", ctx.Err())
		}
		snap, err := ref.Get(ctx)
		close(scheduled)
		return snap, err
	})
	t.Cleanup(func() { server.StubBookingScheduleRead(nil) })

	body, err := json.Marshal(protocol.BookingBody{
		At:      bookingNow.Add(5 * time.Minute),
		Message: "薬の確認",
		Script:  "ハナさん、お薬は飲みましたか。",
	})
	if err != nil {
		t.Fatal(err)
	}
	errc := make(chan error, 1)
	go func() {
		_, err := postJSONBody(ctx, srv.URL+protocol.BookingPath+"/"+id, "Bearer "+token, string(body))
		errc <- err
	}()
	select {
	case <-scheduled:
	case <-time.After(slowEmulatorBound):
		t.Fatal("読み直しの失敗のあと、予約を予定に入れなかった")
	}
	<-errc
	if reads < 2 {
		t.Fatalf("読み直し = %d 回, want 2 回以上", reads)
	}
	if number, _ := bookingData(t, person, id)["number"].(int64); number != 2 {
		t.Fatalf("番号 = %d, want 2", number)
	}
	waitTimers(t, clk, 3)

	clk.Advance(3 * time.Minute)
	time.Sleep(300 * time.Millisecond)
	if callCount(t, person) != 0 {
		t.Fatal("古い時刻に電話が来た")
	}
	clk.Advance(2 * time.Minute)
	callID, _ := receiveCall(t, calls, "")
	if callData(t, person, callID)["script"] != "ハナさん、お薬は飲みましたか。" {
		t.Fatalf("通話内容 = %v", callData(t, person, callID)["script"])
	}
}

func TestUnsentBookingIsReleasedWhenTheSendContextEnds(t *testing.T) {
	clk := clocktest.New(bookingNow)
	srv, handler := newTaskServerWith(t, clk, allowTaskToken)
	person, token := registerHanako(t, srv.URL)
	forgetBookings(t, person)
	conn := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
	waitConnected(t, handler, person, true)
	clk.WaitForTimers(1)
	id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(2*time.Minute), bookingMsg, bookingWords))
	clk.Advance(2 * time.Minute)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var releases atomic.Int32
	server.StubBeforeBookedSend(func(context.Context) {
		cancel()
		conn.CloseNow()
	})
	server.StubBeforeBookingRelease(func(ctx context.Context) error {
		n := releases.Add(1)
		if ctx.Err() != nil {
			t.Errorf("解除 %d 回目が終わった context だった: %v", n, ctx.Err())
		}
		if n == 1 {
			return errors.New("一時的に戻せない")
		}
		return nil
	})
	t.Cleanup(func() {
		server.StubBeforeBookedSend(nil)
		server.StubBeforeBookingRelease(nil)
	})

	raw, err := json.Marshal(protocol.BookingTask{WatchedPersonID: person, BookingID: id, Number: 1})
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		_, _ = postJSONBody(ctx, srv.URL+protocol.BookingTaskPath, "Bearer "+taskToken, string(raw))
	}()
	deadline := time.Now().Add(slowEmulatorBound)
	for {
		if releases.Load() >= 2 && bookingData(t, person, id)["called"] == false && callCount(t, person) == 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("戻せなかった。解除 = %d、かけた = %v、電話 = %d", releases.Load(), bookingData(t, person, id)["called"], callCount(t, person))
		}
		time.Sleep(10 * time.Millisecond)
	}
	server.StubBeforeBookedSend(nil)
	server.StubBeforeBookingRelease(nil)

	conn = dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
	calls := readPhoneCalls(conn)
	waitConnected(t, handler, person, true)
	again := postTask(t, srv.URL, taskToken, person, id, 1)
	if again.status != http.StatusOK {
		t.Fatalf("戻したあと = %d %s, want 200", again.status, again.body)
	}
	callID, _ := receiveCall(t, calls, "")
	if callCount(t, person) != 1 || bookingData(t, person, id)["callId"] != callID {
		t.Fatalf("電話 = %d、予約の電話 = %v", callCount(t, person), bookingData(t, person, id)["callId"])
	}
}

func TestBookingTimer(t *testing.T) {
	t.Run("時刻になると電話機にかけ、出なければ出なかったになる", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, handler := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		conn := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
		calls := readPhoneCalls(conn)
		waitConnected(t, handler, person, true)
		clk.WaitForTimers(1)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(3*time.Minute), bookingMsg, bookingWords))
		waitTimers(t, clk, 2)

		clk.Advance(3 * time.Minute)
		callID, _ := receiveCall(t, calls, "")
		if callData(t, person, callID)["script"] != bookingWords || bookingData(t, person, id)["callId"] != callID {
			t.Fatal("予約の時刻に、予約の通話内容でかけていない")
		}
		sendPhoneState(t, conn, callID, protocol.StateMissed)
		waitCallState(t, person, callID, protocol.StateMissed)
	})

	t.Run("電話機がつながっていなければ 1 分おきにやり直し、10 分後につながらなかったにする", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, _ := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		at := bookingNow.Add(2 * time.Minute)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, at, bookingMsg, bookingWords))
		waitTimers(t, clk, 1)

		clk.Advance(2 * time.Minute)
		for range 9 {
			waitTimers(t, clk, 1)
			if bookingData(t, person, id)["called"] != false || callCount(t, person) != 0 {
				t.Fatal("10 分より前に予約を終えた")
			}
			clk.Advance(time.Minute)
		}
		waitTimers(t, clk, 1)
		if bookingData(t, person, id)["called"] != false {
			t.Fatal("9 分後に予約を終えた")
		}
		clk.Advance(time.Minute)

		deadline := time.Now().Add(slowEmulatorBound)
		var call map[string]any
		for {
			if bookingData(t, person, id)["called"] == true && callCount(t, person) == 1 {
				_, call = onlyCall(t, person)
				break
			}
			if time.Now().After(deadline) {
				t.Fatal("10 分後もつながらなかった電話が残っていない")
			}
			time.Sleep(10 * time.Millisecond)
		}
		created, _ := call["createdAt"].(time.Time)
		if call["state"] != protocol.StateFailed || !created.Equal(at) || call["message"] != bookingMsg {
			t.Fatalf("電話 = %v, want 予約した時刻のつながらなかった", call)
		}
	})

	t.Run("動き直したあとに、まだかけていない予約を読み直して時刻にかける", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, handler := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(3*time.Minute), bookingMsg, bookingWords))
		waitTimers(t, clk, 1)
		handler.Stop()

		srv, handler = newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		conn := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
		calls := readPhoneCalls(conn)
		waitConnected(t, handler, person, true)
		waitTimers(t, clk, 2)
		clk.Advance(3 * time.Minute)

		callID, _ := receiveCall(t, calls, "")
		if bookingData(t, person, id)["callId"] != callID || callData(t, person, callID)["message"] != bookingMsg {
			t.Fatal("動き直したあとの予約が、時刻にかかっていない")
		}
	})

	t.Run("直したあとの古い時刻にはかけず、新しい時刻に新しい通話内容でかける", func(t *testing.T) {
		clk := clocktest.New(bookingNow)
		srv, handler := newDemoServerWith(t, "demo-kazokuai", protocol.DevPhoneSecret, clk)
		person, token := registerHanako(t, srv.URL)
		forgetBookings(t, person)
		conn := dialPhone(t, srv.URL, person, protocol.DevPhoneSecret)
		calls := readPhoneCalls(conn)
		waitConnected(t, handler, person, true)
		clk.WaitForTimers(1)
		id := createdBooking(t, postBooking(t, srv.URL, protocol.BookingPath, token, bookingNow.Add(3*time.Minute), bookingMsg, bookingWords))
		edited := postBooking(t, srv.URL, protocol.BookingPath+"/"+id, token, bookingNow.Add(5*time.Minute), "薬の確認", "ハナさん、お薬は飲みましたか。")
		if edited.status != http.StatusOK {
			t.Fatalf("直す = %d %s", edited.status, edited.body)
		}
		waitTimers(t, clk, 3)

		clk.Advance(3 * time.Minute)
		time.Sleep(300 * time.Millisecond)
		if callCount(t, person) != 0 {
			t.Fatal("古い時刻に電話が来た")
		}
		clk.Advance(2 * time.Minute)
		callID, _ := receiveCall(t, calls, "")
		if callData(t, person, callID)["script"] != "ハナさん、お薬は飲みましたか。" {
			t.Fatalf("通話内容 = %v", callData(t, person, callID)["script"])
		}
	})
}

func allowTaskToken(_ context.Context, token, audience string) (string, error) {
	if audience != taskAudience || token != taskToken {
		return "", errors.New("違うトークン")
	}
	return taskAccount, nil
}

func newTaskServer(t *testing.T, clk *clocktest.Clock, check func(context.Context, string, string) (string, error)) *httptest.Server {
	t.Helper()
	srv, _ := newTaskServerWith(t, clk, check)
	return srv
}

func newTaskServerWith(t *testing.T, clk *clocktest.Clock, check func(context.Context, string, string) (string, error)) (*httptest.Server, *server.Handler) {
	t.Helper()
	handler := server.New(server.Config{
		ProjectID:        "kazokuai-prod",
		PhoneSecret:      protocol.DevPhoneSecret,
		TasksAudience:    taskAudience,
		TasksAccount:     taskAccount,
		CheckBookingOIDC: check,
	}, emulators, nil, nil, clk)
	srv := httptest.NewServer(handler)
	t.Cleanup(func() {
		handler.Stop()
		srv.Close()
	})
	return srv, handler
}

func postBooking(t *testing.T, backend, path, token string, at time.Time, message, script string) response {
	t.Helper()
	body, err := json.Marshal(protocol.BookingBody{At: at, Message: message, Script: script})
	if err != nil {
		t.Fatal(err)
	}
	authorization := ""
	if token != "" {
		authorization = "Bearer " + token
	}
	return postJSON(t, backend, path, authorization, string(body))
}

func postTask(t *testing.T, backend, token, personID, bookingID string, number int64) response {
	t.Helper()
	body, err := json.Marshal(protocol.BookingTask{
		WatchedPersonID: personID,
		BookingID:       bookingID,
		Number:          number,
	})
	if err != nil {
		t.Fatal(err)
	}
	authorization := ""
	if token != "" {
		authorization = "Bearer " + token
	}
	return postJSON(t, backend, protocol.BookingTaskPath, authorization, string(body))
}

func createdBooking(t *testing.T, resp response) string {
	t.Helper()
	if resp.status != http.StatusCreated {
		t.Fatalf("ステータス = %d, want 201: %s", resp.status, resp.body)
	}
	var created struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(resp.body, &created); err != nil || created.ID == "" {
		t.Fatalf("本文 = %s, want 予約の ID", resp.body)
	}
	return created.ID
}

func assertBookingError(t *testing.T, resp response, status int, code string) {
	t.Helper()
	if resp.status != status || !strings.Contains(string(resp.body), code) {
		t.Fatalf("答え = %d %s, want %d %s", resp.status, resp.body, status, code)
	}
}

func registerPerson(t *testing.T, backend, name, callName string) (personID, idToken string) {
	t.Helper()
	family := signUp(t)
	body, err := json.Marshal(map[string]string{"name": name, "callName": callName})
	if err != nil {
		t.Fatal(err)
	}
	resp := postJSON(t, backend, "/watched-persons", "Bearer "+family.IDToken, string(body))
	if resp.status != http.StatusCreated {
		t.Fatalf("登録 = %d, want 201: %s", resp.status, resp.body)
	}
	var created struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(resp.body, &created); err != nil || created.ID == "" {
		t.Fatalf("登録の本文 = %s", resp.body)
	}
	return created.ID, family.IDToken
}

func forgetBookings(t *testing.T, personID string) {
	t.Helper()
	t.Cleanup(func() {
		ctx := context.Background()
		docs, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("bookings").Documents(ctx).GetAll()
		if err != nil {
			t.Errorf("予約を読めなかった: %v", err)
			return
		}
		for _, doc := range docs {
			if _, err := doc.Ref.Delete(ctx); err != nil {
				t.Errorf("予約 %s を消せなかった: %v", doc.Ref.ID, err)
			}
		}
	})
}

func bookingsOf(t *testing.T, personID string) []map[string]any {
	t.Helper()
	docs, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("bookings").Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	var got []map[string]any
	for _, doc := range docs {
		got = append(got, doc.Data())
	}
	return got
}

func bookingData(t *testing.T, personID, id string) map[string]any {
	t.Helper()
	doc, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("bookings").Doc(id).Get(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	return doc.Data()
}

func callData(t *testing.T, personID, callID string) map[string]any {
	t.Helper()
	doc, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Doc(callID).Get(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	return doc.Data()
}

func onlyCall(t *testing.T, personID string) (string, map[string]any) {
	t.Helper()
	docs, err := emulators.Firestore.Collection("watchedPersons").Doc(personID).Collection("calls").Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(docs) != 1 {
		t.Fatalf("電話 = %d 件, want 1", len(docs))
	}
	return docs[0].Ref.ID, docs[0].Data()
}

// receiveCall は、電話機に届いた電話を返す。want が空でなければ、その ID であることも確かめる。
func receiveCall(t *testing.T, calls <-chan protocol.PhoneMessage, want string) (string, protocol.PhoneMessage) {
	t.Helper()
	select {
	case got := <-calls:
		if want != "" && got.CallID != want {
			t.Fatalf("届いた電話 = %s, want %s", got.CallID, want)
		}
		return got.CallID, got
	case <-time.After(slowEmulatorBound):
		t.Fatal("電話機に電話が来なかった")
	}
	return "", protocol.PhoneMessage{}
}

func waitTimers(t *testing.T, clk *clocktest.Clock, n int) {
	t.Helper()
	done := make(chan struct{})
	go func() {
		clk.WaitForTimers(n)
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(slowEmulatorBound):
		t.Fatalf("タイマーが %d 個にならなかった", n)
	}
}
