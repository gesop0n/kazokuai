package phone_test

import (
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

// morning は、報告のテストで電話を始める時刻である。ほかのテストの時刻と重ねない。
var morning = time.Date(2026, 11, 7, 6, 0, 0, 0, time.UTC)

func TestCallReport(t *testing.T) {
	t.Run("受話器が上がった電話が終わると、始まりの時刻と長さと発話が Firestore に残る", func(t *testing.T) {
		s := newSystem(t, hanako, morning)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")

		s.clock.advance(10 * time.Second)
		session.reply(finished(outputTranscription("おはようございます。")))
		s.terminal.waitForLines(t, "かぞくAI: おはようございます。")
		s.clock.advance(20 * time.Second)
		session.reply(finished(inputTranscription("朝ごはんも食べたしね。")))
		s.terminal.waitForLines(t, "見守る方: 朝ごはんも食べたしね。")
		s.clock.advance(5 * time.Second)
		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
		}

		call := waitCall(t, morning)
		data := call.Data()
		if got, ok := data["startedAt"].(time.Time); !ok || !got.Equal(morning) {
			t.Errorf("始まりの時刻 = %v, want %v", data["startedAt"], morning)
		}
		if got := intField(t, data, "durationMs"); got != 35_000 {
			t.Errorf("長さ = %d ミリ秒, want 35000", got)
		}
		got := utterancesOf(t, call.Ref)
		want := []storedUtterance{
			{speaker: "AI", offsetMs: 10_000, text: "おはようございます。"},
			{speaker: "見守る方", offsetMs: 30_000, text: "朝ごはんも食べたしね。"},
		}
		if len(got) != len(want) {
			t.Fatalf("発話 = %+v, want %+v", got, want)
		}
		for i := range want {
			if got[i] != want[i] {
				t.Errorf("発話[%d] = %+v, want %+v", i, got[i], want[i])
			}
		}
	})

	t.Run("受話器が上がらなかった電話は、報告しない", func(t *testing.T) {
		started := morning.Add(time.Hour)
		s := newSystem(t, hanako, started)
		c := s.startCall(t)
		s.gemini.waitForSession(t, 1)
		waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)
		before := len(callsOf(t))

		s.clock.advance(time.Minute)

		err := c.result(t)
		if err == nil {
			t.Fatal("見守る方が出なかったのに、電話が無事に終わった")
		}
		if got := len(callsOf(t)); got != before {
			t.Errorf("電話の件数 = %d, want 報告しないので %d", got, before)
		}
	})
}

func waitCall(t *testing.T, started time.Time) *firestore.DocumentSnapshot {
	t.Helper()
	var found *firestore.DocumentSnapshot
	waitUntil(t, "電話が Firestore に残らなかった", func() bool {
		for _, doc := range callsOf(t) {
			got, ok := doc.Data()["startedAt"].(time.Time)
			if ok && got.Equal(started) {
				found = doc
				return true
			}
		}
		return false
	})
	return found
}

func callsOf(t *testing.T) []*firestore.DocumentSnapshot {
	t.Helper()
	docs, err := emulators.Firestore.Collection("watchedPersons").Doc(hanako.WatchedPerson).
		Collection("calls").Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	return docs
}

type storedUtterance struct {
	speaker  string
	offsetMs int64
	text     string
}

func utterancesOf(t *testing.T, call *firestore.DocumentRef) []storedUtterance {
	t.Helper()
	docs, err := call.Collection("utterances").Documents(t.Context()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	got := make([]storedUtterance, len(docs))
	for _, doc := range docs {
		data := doc.Data()
		index := int(intField(t, data, "index"))
		if index < 0 || index >= len(got) {
			t.Fatalf("発話の順番 = %d, 件数は %d", index, len(got))
		}
		got[index] = storedUtterance{
			speaker:  data["speaker"].(string),
			offsetMs: intField(t, data, "offsetMs"),
			text:     data["text"].(string),
		}
	}
	return got
}

func intField(t *testing.T, data map[string]any, name string) int64 {
	t.Helper()
	switch n := data[name].(type) {
	case int64:
		return n
	case int:
		return int64(n)
	default:
		t.Fatalf("%s = %T(%v), want 整数", name, data[name], data[name])
		return 0
	}
}
