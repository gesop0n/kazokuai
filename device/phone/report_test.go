package phone_test

import (
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/gesop0n/kazokuai/internal/protocol"
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

	t.Run("先に始まった発話が、文字起こしが終わる順に関わらず、会話の前に残る", func(t *testing.T) {
		started := morning.Add(6 * time.Hour)
		s := newSystem(t, hanako, started)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")

		// 見守る方の発話を先に始め、その処理が終わってから AI の発話を始める。
		// 音声は、前の文字起こしを扱ったしるしに使う。発話そのものにはしない。
		s.clock.advance(time.Second)
		session.reply(inputTranscription("朝ごはんも"))
		session.reply(aiAudio(1))
		waitUntil(t, "見守る方の発話の開始を扱わなかった", func() bool { return len(s.phone.playedAudio()) == 1 })

		s.clock.advance(time.Second)
		session.reply(outputTranscription("おはよう"))
		session.reply(aiAudio(2))
		waitUntil(t, "AI の発話の開始を扱わなかった", func() bool { return len(s.phone.playedAudio()) == 2 })

		session.reply(finished(outputTranscription("ございます。")))
		s.terminal.waitForLines(t, "かぞくAI: おはようございます。")
		session.reply(finished(inputTranscription("食べたしね。")))
		s.terminal.waitForLines(t, "見守る方: 朝ごはんも食べたしね。")
		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
		}

		got := utterancesOf(t, waitCall(t, started).Ref)
		want := []storedUtterance{
			{speaker: "見守る方", offsetMs: 1_000, text: "朝ごはんも食べたしね。"},
			{speaker: "AI", offsetMs: 2_000, text: "おはようございます。"},
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

	t.Run("終わりの印がなくても、やり取りは始まった順の行になり、それぞれの時刻を持つ", func(t *testing.T) {
		started := morning.Add(9 * time.Hour)
		s := newSystem(t, hanako, started)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")

		session.reply(outputTranscription("おはようございます。"), generationComplete())
		s.terminal.waitForLines(t, "かぞくAI: おはようございます。")

		// 文字起こしは話し終えたあとに届く。行の時刻は、そのときではなく話し始めの音声の時刻である。
		s.clock.advance(8 * time.Second)
		session.reply(voiceActivity(8 * time.Second))
		s.clock.advance(2 * time.Second)
		session.reply(
			inputTranscription("朝に おにぎり 食べ て 昼 は ラーメン を 食べ た よ 。"),
			voiceActivity(9500*time.Millisecond),
		)
		s.terminal.waitForLines(t, "見守る方: 朝におにぎり食べて昼はラーメンを食べたよ。")

		s.clock.advance(10 * time.Second)
		session.reply(outputTranscription("それはよかったです。"), generationComplete())
		s.terminal.waitForLines(t, "かぞくAI: それはよかったです。")

		s.clock.advance(8 * time.Second)
		session.reply(voiceActivity(28 * time.Second))
		s.clock.advance(2 * time.Second)
		session.reply(inputTranscription("hello world"), voiceActivity(29*time.Second))
		s.terminal.waitForLines(t, "見守る方: hello world")

		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
		}

		got := utterancesOf(t, waitCall(t, started).Ref)
		want := []storedUtterance{
			{speaker: "AI", offsetMs: 0, text: "おはようございます。"},
			{speaker: "見守る方", offsetMs: 8_000, text: "朝におにぎり食べて昼はラーメンを食べたよ。"},
			{speaker: "AI", offsetMs: 20_000, text: "それはよかったです。"},
			{speaker: "見守る方", offsetMs: 28_000, text: "hello world"},
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

	t.Run("受話器が上がらなかった電話は、出なかったになり、発話も始まりの時刻も残らない", func(t *testing.T) {
		started := morning.Add(time.Hour)
		s := newSystem(t, hanako, started)
		c := s.startCall(t)
		s.gemini.waitForSession(t, 1)
		waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)

		s.clock.advance(time.Minute)

		err := c.result(t)
		if err == nil {
			t.Fatal("見守る方が出なかったのに、電話が無事に終わった")
		}
		doc := waitState(t, c.id, protocol.StateMissed)
		if _, ok := doc.Data()["startedAt"].(time.Time); ok {
			t.Error("出なかった電話に始まりの時刻がある")
		}
		if got := utterancesOf(t, doc.Ref); len(got) != 0 {
			t.Errorf("発話 = %+v, want 残さない", got)
		}
	})
}

// TestReviewInputFragmentsAcrossGenerationComplete は、見守る方の同じ発話の末尾が
// モデルの生成完了より遅れて、終わりの印付きで届いても、1 行のまま残ることを確かめる。
// 入力の文字起こしとモデルの通知には、到着順の保証がない。
func TestReviewInputFragmentsAcrossGenerationComplete(t *testing.T) {
	started := morning.Add(13 * time.Hour)
	s := newSystem(t, hanako, started)
	c := s.startCall(t)
	session := s.gemini.waitForSession(t, 1)
	s.phone.pickUp()
	waitForText(t, session, "[電話がつながりました]")

	s.clock.advance(time.Second)
	session.reply(inputTranscription("朝ごはんを"), aiAudio(1))
	waitUntil(t, "見守る方の発話の開始を扱わなかった", func() bool { return len(s.phone.playedAudio()) == 1 })

	s.clock.advance(time.Second)
	session.reply(outputTranscription("そうですか。"), generationComplete())
	s.terminal.waitForLines(t, "かぞくAI: そうですか。")

	s.clock.advance(time.Second)
	session.reply(finished(inputTranscription("食べました。")), aiAudio(2))
	waitUntil(t, "遅れて届いた見守る方の発話を扱わなかった", func() bool { return len(s.phone.playedAudio()) == 2 })

	s.phone.putDown()
	if err := c.result(t); err != nil {
		t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
	}

	got := utterancesOf(t, waitCall(t, started).Ref)
	if len(got) != 2 {
		t.Fatalf("生成完了をまたいだ同じ発話が分かれた: %+v", got)
	}
	if got[0].speaker != "見守る方" || got[0].text != "朝ごはんを食べました。" || got[0].offsetMs != 1000 {
		t.Fatalf("見守る方の発話 = %+v, want 1 秒の「朝ごはんを食べました。」", got)
	}
}

// TestReviewInterruptedModelUtterancesStaySeparate は、割り込まれた AI の発話が
// 次の返答と 1 行にならないことを確かめる。割り込まれたターンには、生成完了が来ない。
func TestReviewInterruptedModelUtterancesStaySeparate(t *testing.T) {
	started := morning.Add(14 * time.Hour)
	s := newSystem(t, hanako, started)
	c := s.startCall(t)
	session := s.gemini.waitForSession(t, 1)
	s.phone.pickUp()
	waitForText(t, session, "[電話がつながりました]")

	s.clock.advance(time.Second)
	session.reply(outputTranscription("今日はいい天気で"), aiAudio(1))
	waitUntil(t, "AI の発話の開始を扱わなかった", func() bool { return len(s.phone.playedAudio()) == 1 })

	session.reply(interrupted(), turnComplete())
	waitUntil(t, "割り込みを扱わなかった", func() bool { return s.phone.hushCount() == 1 })

	s.clock.advance(time.Second)
	session.reply(inputTranscription("朝ごはんの話をしたいです。"), aiAudio(2))
	waitUntil(t, "見守る方の発話を扱わなかった", func() bool { return len(s.phone.playedAudio()) == 2 })

	s.clock.advance(time.Second)
	session.reply(outputTranscription("何を食べましたか。"), generationComplete(), aiAudio(3))
	waitUntil(t, "次の AI の発話を扱わなかった", func() bool { return len(s.phone.playedAudio()) == 3 })

	s.phone.putDown()
	if err := c.result(t); err != nil {
		t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
	}

	got := utterancesOf(t, waitCall(t, started).Ref)
	want := []storedUtterance{
		{speaker: "AI", offsetMs: 1000, text: "今日はいい天気で"},
		{speaker: "見守る方", offsetMs: 2000, text: "朝ごはんの話をしたいです。"},
		{speaker: "AI", offsetMs: 3000, text: "何を食べましたか。"},
	}
	if len(got) != len(want) {
		t.Fatalf("発話 = %+v, want %+v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("発話[%d] = %+v, want %+v", i, got[i], want[i])
		}
	}
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
	docs, err := emulators.Firestore.Collection("watchedPersons").Doc(hanakoID).
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
