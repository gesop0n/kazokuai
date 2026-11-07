package phone_test

import (
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/backend/server"
)

var hanako = server.Config{
	Name:     "山田花子",
	CallName: "ハナさん",
	Model:    "gemini-3.8-live",
	Voice:    "Kore",
}

// 日本時間では 2026 年 11 月 7 日(土)の 14 時 30 分である。
var saturdayAfternoon = time.Date(2026, 11, 7, 5, 30, 0, 0, time.UTC)

func TestRinging(t *testing.T) {
	t.Run("呼び出しが始まると、トークンをもらって Live API につなぎ、呼び出し音を鳴らしてランプを点ける", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)

		session := s.gemini.waitForSession(t, 1)
		waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)
		waitUntil(t, "ランプが点かなかった", s.phone.isLit)

		if session.token != "auth_tokens/1" {
			t.Errorf("つないだトークン = %q, want バックエンドが作った auth_tokens/1", session.token)
		}
		if session.model != "gemini-3.8-live" {
			t.Errorf("つないだモデル = %q, want gemini-3.8-live", session.model)
		}
		if sent := session.sent(); len(sent) != 0 {
			t.Errorf("受話器が上がる前に Gemini に %d 個のメッセージを送った: %+v", len(sent), sent)
		}
	})
}

func TestPickUp(t *testing.T) {
	t.Run("受話器が上がると、呼び出し音を止め、始まりの合図を文字の発話で送り、それからマイクの音を送る", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)

		s.phone.roomNoise([]byte("部屋の音"))
		s.phone.pickUp()
		s.phone.say(t, []byte("もしもし"))
		waitUntil(t, "見守る方の声が Gemini に届かなかった", func() bool { return len(session.sentAudio()) > 0 })

		if s.phone.isRinging() {
			t.Error("受話器が上がっても呼び出し音が鳴っている")
		}
		sent := session.sent()
		cue, ok := sent[0].(genai.LiveClientContentInput)
		if !ok {
			t.Fatalf("最初に送ったもの = %+v, want 始まりの合図", sent[0])
		}
		if len(cue.Turns) != 1 || cue.Turns[0].Role != genai.RoleUser ||
			len(cue.Turns[0].Parts) != 1 || cue.Turns[0].Parts[0].Text != "[電話がつながりました]" {
			t.Errorf("始まりの合図 = %s, want 見守る方の発話の [電話がつながりました]", turnsString(cue.Turns))
		}
		if cue.TurnComplete == nil || !*cue.TurnComplete {
			t.Error("始まりの合図で発話を終えていないので、AI が話し始めない")
		}
		audio := session.sentAudio()
		if len(audio) != 1 || string(audio[0].Data) != "もしもし" {
			t.Errorf("Gemini に届いたマイクの音 = %q, want 受話器が上がってからの もしもし だけ", audioStrings(audio))
		}
		if audio[0].MIMEType != "audio/pcm;rate=16000" {
			t.Errorf("マイクの音の MIME タイプ = %q, want audio/pcm;rate=16000", audio[0].MIMEType)
		}
	})
}

func TestTalking(t *testing.T) {
	t.Run("AI の音声を受話器で流し、両方の文字起こしを 1 行ずつ出す", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()

		session.reply(
			outputTranscription("ハナさん、"),
			aiAudio(1, 2, 3, 4),
			outputTranscription("こんにちは。"),
			turnComplete(),
			inputTranscription("はい、"),
			inputTranscription("元気です。"),
			outputTranscription("よかったです。"),
			aiAudio(5, 6),
			turnComplete(),
		)

		s.terminal.waitForLines(t,
			"かぞくAI: ハナさん、こんにちは。",
			"見守る方: はい、元気です。",
			"かぞくAI: よかったです。",
		)
		waitUntil(t, "AI の音声を流し終えなかった", func() bool { return len(s.phone.playedAudio()) == 6 })
		if got := s.phone.playedAudio(); string(got) != string([]byte{1, 2, 3, 4, 5, 6}) {
			t.Errorf("受話器で流した音 = %v, want [1 2 3 4 5 6]", got)
		}
	})

	t.Run("見守る方が AI の話に割って入ると、まだ流していない AI の音声を捨て、AI がそこまで話したことを出す", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()

		session.reply(
			outputTranscription("今日は"),
			aiAudio(1, 2),
			inputTranscription("あのね、"),
			interrupted(),
			inputTranscription("聞いてほしいの。"),
			turnComplete(),
		)

		s.terminal.waitForLines(t,
			"かぞくAI: 今日は",
			"見守る方: あのね、聞いてほしいの。",
		)
		if s.phone.hushCount() != 1 {
			t.Errorf("AI の音声を捨てた回数 = %d, want 1", s.phone.hushCount())
		}
	})

	t.Run("発話の終わりの印が付いた文字起こしは、次の発話を待たずにその行を出す", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()

		// AI が答えない発話も、次の発話とつなげずに 1 行で出す
		session.reply(
			finished(outputTranscription("こんにちは。")),
			finished(inputTranscription("はい。")),
			finished(inputTranscription("いい天気ね。")),
		)

		s.terminal.waitForLines(t,
			"かぞくAI: こんにちは。",
			"見守る方: はい。",
			"見守る方: いい天気ね。",
		)
	})
}

func TestPutDown(t *testing.T) {
	t.Run("通話中に受話器を置くと、電話が終わり、Live API との接続を閉じてランプを消す", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		session.reply(outputTranscription("ハナさん、こんにちは。"), aiAudio(1, 2))
		waitUntil(t, "AI の音声を流さなかった", func() bool { return len(s.phone.playedAudio()) == 2 })

		s.phone.putDown()

		if err := c.result(t); err != nil {
			t.Errorf("受話器を置いたのに、電話が %v で終わった", err)
		}
		if !session.isClosed() {
			t.Error("電話が終わっても Live API との接続を閉じていない")
		}
		if s.phone.isLit() {
			t.Error("電話が終わってもランプが点いている")
		}
		s.terminal.waitForLines(t, "かぞくAI: ハナさん、こんにちは。")
	})

	t.Run("Gemini への送信が詰まっていても、受話器を置くと電話が終わり、接続を閉じる", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		session.stall()
		s.phone.pickUp()
		s.phone.say(t, []byte("もしもし"))

		s.phone.putDown()

		if err := c.result(t); err != nil {
			t.Errorf("受話器を置いたのに、電話が %v で終わった", err)
		}
		if !session.isClosed() {
			t.Error("電話が終わっても Live API との接続を閉じていない")
		}
	})
}

func TestConnectionLost(t *testing.T) {
	reason := errors.New("websocket: close 1011 (internal server error): サーバーの都合で切れました")

	t.Run("通話中に接続が切れると、電話を終えて理由を返し、自分からかけ直さない", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		s.phone.say(t, []byte("もしもし"))

		session.drop(reason)

		err := c.result(t)
		if err == nil || !strings.Contains(err.Error(), "サーバーの都合で切れました") {
			t.Errorf("電話が終わった理由 = %v, want 接続が切れた理由を含む", err)
		}
		if s.phone.isLit() {
			t.Error("電話が終わってもランプが点いている")
		}
		if n := len(s.gemini.tokenConfigs()); n != 1 {
			t.Errorf("トークンを %d 回作った, want かけ直さないので 1 回", n)
		}
		if n := s.gemini.sessionCount(); n != 1 {
			t.Errorf("Live API に %d 回つないだ, want かけ直さないので 1 回", n)
		}
	})

	t.Run("サーバーが GoAway で接続を終えると知らせてきたら、電話を終えて理由を返す", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()

		session.reply(&genai.LiveServerMessage{GoAway: &genai.LiveServerGoAway{TimeLeft: 10 * time.Second}})

		if err := c.result(t); err == nil || !strings.Contains(err.Error(), "GoAway") {
			t.Errorf("電話が終わった理由 = %v, want GoAway を受けたこと", err)
		}
		if !session.isClosed() {
			t.Error("電話が終わっても Live API との接続を閉じていない")
		}
		if n := s.gemini.sessionCount(); n != 1 {
			t.Errorf("Live API に %d 回つないだ, want かけ直さないので 1 回", n)
		}
	})

	t.Run("呼び出し中に接続が切れると、呼び出し音を止めて電話を終える", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)

		session.drop(reason)

		if err := c.result(t); err == nil || !strings.Contains(err.Error(), "サーバーの都合で切れました") {
			t.Errorf("電話が終わった理由 = %v, want 接続が切れた理由を含む", err)
		}
		if s.phone.isRinging() {
			t.Error("電話が終わっても呼び出し音が鳴っている")
		}
		if s.phone.isLit() {
			t.Error("電話が終わってもランプが点いている")
		}
	})
}

func TestToken(t *testing.T) {
	t.Run("トークンは 1 回だけ使え、モデルと設定の全体を固定する", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)
		s.gemini.waitForSession(t, 1)

		token := s.gemini.tokenConfigs()[0]
		if token.Uses == nil || *token.Uses != 1 {
			t.Errorf("トークンを使える回数 = %v, want 1", token.Uses)
		}
		if token.LockAdditionalFields != nil {
			t.Errorf("追加で固定するフィールド = %v, want 指定しないで、すべてのフィールドを固定する", token.LockAdditionalFields)
		}
		constraints := token.LiveConnectConstraints
		if constraints == nil || constraints.Config == nil {
			t.Fatalf("トークンの制約 = %+v, want モデルと設定を固定する", constraints)
		}
		if constraints.Model != "gemini-3.8-live" {
			t.Errorf("固定したモデル = %q, want gemini-3.8-live", constraints.Model)
		}
		config := constraints.Config
		if len(config.ResponseModalities) != 1 || config.ResponseModalities[0] != genai.ModalityAudio {
			t.Errorf("AI の答え方 = %v, want 音声だけ", config.ResponseModalities)
		}
		if voice := voiceName(config); voice != "Kore" {
			t.Errorf("固定した声 = %q, want Kore", voice)
		}
		if config.InputAudioTranscription == nil {
			t.Error("見守る方の声を文字起こししない")
		}
		if config.OutputAudioTranscription == nil {
			t.Error("AI の声を文字起こししない")
		}
	})

	t.Run("システム指示に、見守る方の名前と呼び方、日本時間の今の日時、AI であること、始まりの合図を書く", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)
		s.gemini.waitForSession(t, 1)

		instruction := systemInstruction(t, s.gemini.tokenConfigs()[0])
		for _, want := range []string{
			"山田花子",
			"ハナさん",
			"2026年11月7日",
			"14時30分",
			"かぞくAI",
			"家族",
			"[電話がつながりました]",
		} {
			if !strings.Contains(instruction, want) {
				t.Errorf("システム指示に %q がない:\n%s", want, instruction)
			}
		}
	})

	t.Run("電話ごとに新しいトークンをもらう", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		for n := 1; n <= 2; n++ {
			c := s.startCall(t)
			session := s.gemini.waitForSession(t, n)
			s.phone.pickUp()
			s.phone.putDown()
			if err := c.result(t); err != nil {
				t.Fatalf("%d 回目の電話が %v で終わった", n, err)
			}
			if want := fmt.Sprintf("auth_tokens/%d", n); session.token != want {
				t.Errorf("%d 回目の電話でつないだトークン = %q, want %q", n, session.token, want)
			}
		}
	})
}

func voiceName(config *genai.LiveConnectConfig) string {
	if config.SpeechConfig == nil || config.SpeechConfig.VoiceConfig == nil ||
		config.SpeechConfig.VoiceConfig.PrebuiltVoiceConfig == nil {
		return ""
	}
	return config.SpeechConfig.VoiceConfig.PrebuiltVoiceConfig.VoiceName
}

func systemInstruction(t *testing.T, token *genai.CreateAuthTokenConfig) string {
	t.Helper()
	if token.LiveConnectConstraints == nil || token.LiveConnectConstraints.Config == nil ||
		token.LiveConnectConstraints.Config.SystemInstruction == nil {
		t.Fatal("トークンにシステム指示を固定していない")
	}
	var b strings.Builder
	for _, part := range token.LiveConnectConstraints.Config.SystemInstruction.Parts {
		b.WriteString(part.Text)
	}
	return b.String()
}

func turnsString(turns []*genai.Content) string {
	var b strings.Builder
	for _, turn := range turns {
		fmt.Fprintf(&b, "%s:", turn.Role)
		for _, part := range turn.Parts {
			fmt.Fprintf(&b, " %q", part.Text)
		}
		b.WriteString("; ")
	}
	return b.String()
}

func audioStrings(audio []*genai.Blob) []string {
	var s []string
	for _, blob := range audio {
		s = append(s, string(blob.Data))
	}
	return s
}
