package phone_test

import (
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/gesop0n/kazokuai/internal/firebasetest"
	"github.com/gesop0n/kazokuai/internal/protocol"
)

func TestCallMovesThroughStates(t *testing.T) {
	started := time.Date(2026, 11, 8, 1, 0, 0, 0, time.UTC)
	s := newSystem(t, hanako, started)
	c := s.startCall(t)
	session := s.gemini.waitForSession(t, 1)
	waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)

	ringing := waitState(t, c.id, protocol.StateRinging)
	if ringing.Data()["message"] != testMessage {
		t.Errorf("伝えたいこと = %v, want %s", ringing.Data()["message"], testMessage)
	}
	if ringing.Data()["script"] != testScript {
		t.Errorf("通話内容 = %v, want %s", ringing.Data()["script"], testScript)
	}

	s.phone.pickUp()
	waitForText(t, session, "[電話がつながりました]")
	waitState(t, c.id, protocol.StateTalking)
	s.clock.advance(time.Second)
	session.reply(finished(outputTranscription("お伝えします。")))
	s.terminal.waitForLines(t, "かぞくAI: お伝えします。")
	s.phone.putDown()
	if err := c.result(t); err != nil {
		t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
	}

	ended := waitState(t, c.id, protocol.StateEnded)
	if got, ok := ended.Data()["startedAt"].(time.Time); !ok || !got.Equal(started) {
		t.Errorf("始まりの時刻 = %v, want %v", ended.Data()["startedAt"], started)
	}
	got := utterancesOf(t, ended.Ref)
	if len(got) != 1 || got[0].text != "お伝えします。" {
		t.Fatalf("発話 = %+v, want お伝えします。", got)
	}
}

func TestStartCallWhenThePhoneIsOffline(t *testing.T) {
	s := newSystem(t, hanako, time.Date(2026, 11, 8, 2, 0, 0, 0, time.UTC))
	waitUntil(t, "電話機がつながらなかった", func() bool { return s.api.Connected(hanakoID) })
	s.stopPhone(t)
	before := len(callsOf(t))

	status, body, err := postNow(s.backend.URL, familyToken, testMessage, testScript)
	if err != nil {
		t.Fatal(err)
	}
	if status != 409 || !strings.Contains(body, protocol.PhoneNotConnected) {
		t.Fatalf("今すぐ通話 = %d %s, want 409 phone_not_connected", status, body)
	}
	if got := len(callsOf(t)); got != before {
		t.Errorf("電話の件数 = %d, want 作らないので %d", got, before)
	}
	if s.phone.isRinging() {
		t.Error("つながっていない電話機が鳴った")
	}
}

func TestOnlyTheFamilyCanStartACall(t *testing.T) {
	s := newSystem(t, hanako, time.Date(2026, 11, 8, 3, 0, 0, 0, time.UTC))
	waitUntil(t, "電話機がつながらなかった", func() bool { return s.api.Connected(hanakoID) })
	before := len(callsOf(t))

	stranger, err := firebasetest.SignUp(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	status, body, err := postNow(s.backend.URL, stranger.IDToken, testMessage, testScript)
	if err != nil {
		t.Fatal(err)
	}
	if status != 403 {
		t.Fatalf("家族ではない人の今すぐ通話 = %d %s, want 403", status, body)
	}
	if got := len(callsOf(t)); got != before {
		t.Errorf("電話の件数 = %d, want 作らないので %d", got, before)
	}
	if s.phone.isRinging() {
		t.Error("家族ではない人の電話で、ハナさんの電話機が鳴った")
	}

	other, err := firebasetest.SignUp(t.Context())
	if err != nil {
		t.Fatal(err)
	}
	otherID, err := firebasetest.RegisterWatchedPersonAs(t.Context(), s.backend.URL, other, "佐藤一郎", "イチロウさん")
	if err != nil {
		t.Fatal(err)
	}
	status, body, err = postNow(s.backend.URL, other.IDToken, testMessage, testScript)
	if err != nil {
		t.Fatal(err)
	}
	if status != 409 || !strings.Contains(body, protocol.PhoneNotConnected) {
		t.Fatalf("電話機のない家族の今すぐ通話 = %d %s, want 409 phone_not_connected", status, body)
	}
	if s.phone.isRinging() {
		t.Error("別の家族の電話で、ハナさんの電話機が鳴った")
	}
	docs, err := emulators.Firestore.Collection("watchedPersons").Doc(otherID).Collection("calls").Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(docs) != 0 {
		t.Errorf("電話機のない家族の電話 = %d 件, want 作らない", len(docs))
	}
}

func TestPhoneReconnectsAfterTheBackendRestarts(t *testing.T) {
	started := time.Date(2026, 11, 8, 4, 0, 0, 0, time.UTC)
	s := newSystem(t, hanako, started)
	waitUntil(t, "電話機がつながらなかった", func() bool { return s.api.Connected(hanakoID) })

	s.restartBackend(t)

	c := s.startCall(t)
	s.gemini.waitForSession(t, 1)
	waitUntil(t, "つなぎ直したあとに呼び出し音が鳴らなかった", s.phone.isRinging)
	s.phone.pickUp()
	s.phone.putDown()
	if err := c.result(t); err != nil {
		t.Fatalf("つなぎ直したあとの電話が %v で終わった", err)
	}
	waitState(t, c.id, protocol.StateEnded)
}

func TestPhonePlacesASecondCallWithoutRestart(t *testing.T) {
	started := time.Date(2026, 11, 8, 5, 0, 0, 0, time.UTC)
	s := newSystem(t, hanako, started)
	var ids []string
	for range 2 {
		c := s.startCall(t)
		ids = append(ids, c.id)
		s.gemini.waitForSession(t, len(ids))
		waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)
		s.phone.pickUp()
		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatalf("%d 回目の電話が %v で終わった", len(ids), err)
		}
		waitState(t, c.id, protocol.StateEnded)
	}
	if ids[0] == ids[1] {
		t.Fatalf("2 回の電話が同じ ID %s だった", ids[0])
	}
}

func waitState(t *testing.T, id, state string) *firestore.DocumentSnapshot {
	t.Helper()
	var doc *firestore.DocumentSnapshot
	waitUntil(t, "電話が "+state+" にならなかった", func() bool {
		snap, err := emulators.Firestore.Collection("watchedPersons").Doc(hanakoID).Collection("calls").Doc(id).Get(t.Context())
		if err != nil {
			return false
		}
		got, _ := snap.Data()["state"].(string)
		if got != state {
			return false
		}
		doc = snap
		return true
	})
	return doc
}
