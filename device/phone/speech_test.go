package phone_test

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"
)

// TestSpeechBoundaries は、試しで記録した Live の順番を流し、
// 保存される発話とその順番と時刻を確かめる。
// 見守る方の時刻は、文字起こしが届いたときではなく、話し始めの音声の時刻である。
func TestSpeechBoundaries(t *testing.T) {
	t.Run("ひと続きの発話は、AI の文字起こしや生成完了が間に入っても 1 行で、返答が先に届いてもその返答より前に残る", func(t *testing.T) {
		started := morning.Add(16 * time.Hour)
		s := newSystem(t, hanako, started)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")

		// 試しの最初のやり取り。文字と音声の時刻は記録どおりで、
		// 生成完了を発話の欠片のあいだに置き、次の返答は文字起こしより先に届かせる。
		send := atSender(t, s, session, started)
		send(1200, voiceActivity(1120*time.Millisecond))
		send(2000, inputTranscription("おはようございます。"))
		send(3892,
			outputTranscription("おはようございます。今日も良い"),
			outputTranscription(""),
			outputTranscription("お天気ですね。"),
			outputTranscription("体調はいかが"),
			generationComplete(),
		)
		send(4000, inputTranscription("今朝"), voiceActivity(3800*time.Millisecond))
		send(4269, voiceActivity(4120*time.Millisecond))
		send(6136,
			outputTranscription("それは良かったです。しっかり"),
			outputTranscription(""),
			outputTranscription("食べると元気"),
			outputTranscription("が出ますね。"),
			generationComplete(),
		)
		send(6200, inputTranscription("食べました。"), voiceActivity(5880*time.Millisecond))

		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
		}

		text := s.terminal.text()
		if strings.Count(text, "見守る方: おはようございます。今朝\n") != 1 {
			t.Errorf("話し始めから話し終わりまでは 1 行である:\n%s", text)
		}
		got := utterancesOf(t, waitCall(t, started).Ref)
		want := []storedUtterance{
			{speaker: "見守る方", offsetMs: 1120, text: "おはようございます。今朝"},
			{speaker: "AI", offsetMs: 3892, text: "おはようございます。今日も良いお天気ですね。体調はいかが"},
			{speaker: "見守る方", offsetMs: 4120, text: "食べました。"},
			{speaker: "AI", offsetMs: 6136, text: "それは良かったです。しっかり食べると元気が出ますね。"},
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

	t.Run("話の途中で間をあけると発話が分かれ、AI が答え始めたあとに話し続けると、その発話は答えより前に残る", func(t *testing.T) {
		started := morning.Add(18 * time.Hour)
		s := newSystem(t, hanako, started)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")

		// 試しの記録。1.2 秒の間で発話が分かれ、AI が答え始めた直後に見守る方が話し続けて割り込んだ。
		send := atSender(t, s, session, started)
		send(14092, voiceActivity(13680*time.Millisecond))
		send(16033, inputTranscription("昨日"), voiceActivity(15480*time.Millisecond))
		send(16036,
			outputTranscription("はい、昨日どうされましたか?"),
			outputTranscription(""),
			outputTranscription("お話し"),
			outputTranscription("聞かせていただけます"),
			outputTranscription("か?"),
			generationComplete(),
		)
		send(17142, voiceActivity(16600*time.Millisecond), interrupted(), turnComplete())
		send(20247, inputTranscription("でも少し膝が痛いです。"), voiceActivity(19440*time.Millisecond))
		send(20663,
			outputTranscription("それは大変ですね。無理"),
			outputTranscription(""),
			outputTranscription("をなさらず、"),
			outputTranscription("ゆっくり休んでください"),
			outputTranscription("ね。"),
			generationComplete(),
		)

		s.terminal.waitForLines(t,
			"見守る方: 昨日",
			"かぞくAI: はい、昨日どうされましたか?お話し聞かせていただけますか?",
			"見守る方: でも少し膝が痛いです。",
			"かぞくAI: それは大変ですね。無理をなさらず、ゆっくり休んでくださいね。",
		)
		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
		}

		got := utterancesOf(t, waitCall(t, started).Ref)
		want := []storedUtterance{
			{speaker: "見守る方", offsetMs: 13680, text: "昨日"},
			{speaker: "AI", offsetMs: 16036, text: "はい、昨日どうされましたか?お話し聞かせていただけますか?"},
			{speaker: "見守る方", offsetMs: 16600, text: "でも少し膝が痛いです。"},
			{speaker: "AI", offsetMs: 20663, text: "それは大変ですね。無理をなさらず、ゆっくり休んでくださいね。"},
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
}

// atSender は、受話器を上げてから atMs ミリ秒の時刻に Live のメッセージを届ける。
// 最後に短い音声を足し、デバイスがそこまで扱ったことを確かめてから返す。
func atSender(t *testing.T, s *system, session *fakeSession, pickedUp time.Time) func(int, ...*genai.LiveServerMessage) {
	t.Helper()
	return func(atMs int, msgs ...*genai.LiveServerMessage) {
		t.Helper()
		target := time.Duration(atMs) * time.Millisecond
		if lag := target - s.clock.Now().Sub(pickedUp); lag > 0 {
			s.clock.advance(lag)
		}
		n := len(s.phone.playedAudio()) + 1
		session.reply(msgs...)
		session.reply(aiAudio(byte(n)))
		waitUntil(t, fmt.Sprintf("%d ミリ秒のメッセージを扱わなかった", atMs), func() bool {
			return len(s.phone.playedAudio()) >= n
		})
	}
}
