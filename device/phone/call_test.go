package phone_test

import (
	"errors"
	"fmt"
	"reflect"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/backend/server"
)

// hanako は、山田花子さん(呼び方はハナさん)に電話をかけるバックエンドの設定である。
// 見守る方の ID は、TestMain がアプリと同じ API で登録してから入れる。
var hanako = server.Config{
	Model:        "gemini-3.8-live",
	Voice:        "Kore",
	RingTimeout:  time.Minute,
	MaxCall:      5 * time.Minute,
	WrapUpBefore: time.Minute,
	TokenMargin:  5 * time.Minute,
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
			finished(outputTranscription("こんにちは。")),
			inputTranscription("はい、"),
			finished(inputTranscription("元気です。")),
			finished(outputTranscription("よかったです。")),
			aiAudio(5, 6),
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

	t.Run("見守る方が AI の話に割って入ると、まだ流していない AI の音声を捨て、そこまでの AI の発話を区切る", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		c := s.startCall(t)
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

		waitUntil(t, "AI の音声を捨てなかった", func() bool { return s.phone.hushCount() == 1 })
		s.terminal.waitForLines(t, "かぞくAI: 今日は")
		if text := s.terminal.text(); strings.Contains(text, "見守る方:") {
			t.Fatalf("割り込みと相手の文字起こしと TurnComplete では、見守る方の行を区切らない:\n%s", text)
		}

		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
		}
		s.terminal.waitForLines(t,
			"かぞくAI: 今日は",
			"見守る方: あのね、聞いてほしいの。",
		)
	})

	t.Run("2 人の文字起こしが入り交じって届いても、相手の文字起こしや TurnComplete では区切らず、1 つの発話は 1 行のままである", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()

		session.reply(
			outputTranscription("こんにちは、"),
			inputTranscription("うん、"),
			turnComplete(),
			finished(outputTranscription("ハナさん。")),
			finished(inputTranscription("元気です。")),
		)

		want := []string{
			"かぞくAI: こんにちは、ハナさん。",
			"見守る方: うん、元気です。",
		}
		s.terminal.waitForLines(t, want...)
		if got := s.terminal.lines(); !reflect.DeepEqual(got, want) {
			t.Errorf("ターミナル = %q, want %q", got, want)
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
		if n := s.phone.offCount(); n != 1 {
			t.Errorf("ランプを消した回数 = %d, want 1", n)
		}
		s.terminal.waitForLines(t, "かぞくAI: ハナさん、こんにちは。")
	})

	t.Run("報告の応答を待っているあいだに、マイクを止め、まだ流していない音を捨て、接続を閉じてランプを消す", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		c := s.startCall(t)
		s.holdReport()
		t.Cleanup(s.releaseReport)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")
		session.reply(aiAudio(1, 2))
		waitUntil(t, "AI の音声を流さなかった", func() bool { return len(s.phone.playedAudio()) == 2 })

		s.phone.putDown()

		waitUntil(t, "報告がバックエンドに届かなかった", s.reportArrived)
		if c.hasEnded() {
			t.Fatal("報告の応答を待っているあいだに、電話の処理が戻った")
		}
		if !session.isClosed() {
			t.Error("報告の応答を待っているあいだ、Live API との接続が開いている")
		}
		if s.phone.isLit() {
			t.Error("報告の応答を待っているあいだ、ランプが点いている")
		}
		if n := s.phone.offCount(); n != 1 {
			t.Errorf("報告の応答を待っているあいだ、ランプを消した回数 = %d, want 1", n)
		}
		waitUntil(t, "報告の応答を待っているあいだ、マイクが開いている", func() bool { return !s.phone.micOpen() })
		if s.phone.hushCount() == 0 {
			t.Error("報告の応答を待っているあいだ、まだ流していない音を捨てていない")
		}

		s.releaseReport()
		if err := c.result(t); err != nil {
			t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
		}
		if n := s.phone.offCount(); n != 1 {
			t.Errorf("報告が戻ったあとのランプを消した回数 = %d, want 1", n)
		}
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

		err := c.result(t)
		if err == nil || !strings.Contains(err.Error(), "GoAway") || !strings.Contains(err.Error(), "10s") {
			t.Errorf("電話が終わった理由 = %v, want GoAway と残り時間", err)
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

	t.Run("見守る方の文字起こしに、言語のヒントとして ja-JP を指定する", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)
		s.gemini.waitForSession(t, 1)

		token := s.gemini.tokenConfigs()[0]
		if token.LiveConnectConstraints == nil || token.LiveConnectConstraints.Config == nil {
			t.Fatal("トークンに Live API の設定がない")
		}
		transcription := token.LiveConnectConstraints.Config.InputAudioTranscription
		if transcription == nil {
			t.Fatal("見守る方の声を文字起こししない")
		}
		want := []string{"ja-JP"}
		if got := transcription.LanguageCodes; !reflect.DeepEqual(got, want) {
			t.Errorf("見守る方の文字起こしの言語 = %v, want %v", got, want)
		}
	})

	t.Run("システム指示は、締めの合図を受けたら話をまとめて別れの挨拶をするよう伝える", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)
		s.gemini.waitForSession(t, 1)

		instruction := systemInstruction(t, s.gemini.tokenConfigs()[0])
		for _, want := range []string{
			"[あと 1 分で電話を終えます]",
			"話をまとめ",
			"別れの挨拶",
		} {
			if !strings.Contains(instruction, want) {
				t.Errorf("システム指示に %q がない:\n%s", want, instruction)
			}
		}
	})

	t.Run("システム指示に、Firestore にある見守る方の名前と呼び方、日本時間の今の日時、AI であること、始まりの合図を書く", func(t *testing.T) {
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

	t.Run("見守る方を指定せずに起動したバックエンドからはトークンをもらえず、指定するよう伝えて電話を終える", func(t *testing.T) {
		config := hanako
		config.WatchedPerson = ""
		s := newSystem(t, config, saturdayAfternoon)

		err := s.startCall(t).result(t)

		if err == nil || !strings.Contains(err.Error(), "--watched-person") {
			t.Errorf("電話の終わり = %v, want --watched-person で見守る方を指定するよう伝える", err)
		}
		if tokens := s.gemini.tokenConfigs(); len(tokens) != 0 {
			t.Errorf("トークンを %d 個作った, want 作らない", len(tokens))
		}
		if s.phone.isLit() || s.phone.isRinging() {
			t.Error("トークンをもらえないのに、電話機を鳴らした")
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

func TestTokenExpireTime(t *testing.T) {
	t.Run("有効期限は、呼び出しの上限と電話の長さの上限とトークンの余裕の合計で、既定では 11 分である", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		s.startCall(t)
		s.gemini.waitForSession(t, 1)

		got := s.gemini.tokenConfigs()[0].ExpireTime
		want := saturdayAfternoon.Add(11 * time.Minute)
		if !got.Equal(want) {
			t.Errorf("有効期限 = %s, want %s", got, want)
		}
	})

	t.Run("時間のフラグを変えると、有効期限が変わる", func(t *testing.T) {
		config := hanako
		config.RingTimeout = 30 * time.Second
		config.MaxCall = 2 * time.Minute
		config.TokenMargin = time.Minute
		s := newSystem(t, config, saturdayAfternoon)
		s.startCall(t)
		s.gemini.waitForSession(t, 1)

		got := s.gemini.tokenConfigs()[0].ExpireTime
		want := saturdayAfternoon.Add(3*time.Minute + 30*time.Second)
		if !got.Equal(want) {
			t.Errorf("有効期限 = %s, want %s", got, want)
		}
	})
}

func TestRingTimeout(t *testing.T) {
	t.Run("呼び出しの上限を過ぎても受話器が上がらなければ、呼び出しを止め、接続を閉じ、見守る方が出なかったことを出す", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)

		s.advance(t, c, 30*time.Second)
		if c.hasEnded() {
			t.Fatalf("上限は 1 分なのに、30 秒で電話が終わった: %v", c.err)
		}

		s.clock.advance(30 * time.Second)

		err := c.result(t)
		if err == nil || !strings.Contains(err.Error(), "見守る方が出ませんでした") {
			t.Errorf("電話が終わった理由 = %v, want 見守る方が出なかったこと", err)
		}
		if s.phone.isRinging() {
			t.Error("呼び出しの上限を過ぎても呼び出し音が鳴っている")
		}
		if !session.isClosed() {
			t.Error("見守る方が出なくても Live API との接続を閉じていない")
		}
		if s.phone.isLit() {
			t.Error("電話が終わってもランプが点いている")
		}
		if sent := session.sent(); len(sent) != 0 {
			t.Errorf("出なかった電話で Gemini に %d 個のメッセージを送った: %+v", len(sent), sent)
		}
	})

	t.Run("呼び出しの上限を変えると、見守る方が出なかったと出る時刻が変わる", func(t *testing.T) {
		config := hanako
		config.RingTimeout = 30 * time.Second
		s := newSystem(t, config, saturdayAfternoon)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)

		s.clock.advance(30 * time.Second)

		err := c.result(t)
		if err == nil || !strings.Contains(err.Error(), "見守る方が出ませんでした") {
			t.Errorf("電話が終わった理由 = %v, want 見守る方が出なかったこと", err)
		}
		if !session.isClosed() {
			t.Error("見守る方が出なくても Live API との接続を閉じていない")
		}
	})

	t.Run("受話器を上げたあとに呼び出しの上限が来ても、出なかったことにはしない", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")

		s.advance(t, c, time.Minute)

		if c.hasEnded() {
			t.Fatalf("通話中なのに、呼び出しの上限で電話が終わった: %v", c.err)
		}
		if s.phone.isRinging() {
			t.Error("受話器が上がっても呼び出し音が鳴っている")
		}
	})
}

func TestWrapUpAndTimeLimit(t *testing.T) {
	t.Run("上限の 1 分前に締めの合図を送り、上限で電話を終える", func(t *testing.T) {
		s := newSystem(t, hanako, saturdayAfternoon)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")

		s.advance(t, c, 3*time.Minute)
		if c.hasEnded() {
			t.Fatalf("締めの合図より前に電話が終わった: %v", c.err)
		}
		if hasText(session, "[あと 1 分で電話を終えます]") {
			t.Fatal("締めの合図が早い")
		}

		s.clock.advance(time.Minute)
		cue := waitForText(t, session, "[あと 1 分で電話を終えます]")
		if c.hasEnded() {
			t.Fatal("締めの合図のときに電話が終わった")
		}
		if len(cue.Turns) != 1 || cue.Turns[0].Role != genai.RoleUser {
			t.Errorf("締めの合図 = %s, want 見守る方の発話", turnsString(cue.Turns))
		}
		if cue.TurnComplete == nil || !*cue.TurnComplete {
			t.Error("締めの合図で発話を終えていないので、AI が別れの挨拶をしない")
		}

		s.clock.advance(time.Minute)
		if err := c.result(t); err != nil {
			t.Errorf("上限で電話が %v で終わった", err)
		}
		if !session.isClosed() {
			t.Error("上限で電話が終わっても Live API との接続を閉じていない")
		}
		if s.phone.isLit() {
			t.Error("電話が終わってもランプが点いている")
		}
	})

	t.Run("時間のフラグを変えると、締めの合図と電話の終わりが変わる", func(t *testing.T) {
		config := hanako
		config.RingTimeout = 3 * time.Minute
		config.MaxCall = 2 * time.Minute
		config.WrapUpBefore = 30 * time.Second
		config.TokenMargin = time.Minute
		s := newSystem(t, config, saturdayAfternoon)
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		waitUntil(t, "呼び出し音が鳴らなかった", s.phone.isRinging)

		instruction := systemInstruction(t, s.gemini.tokenConfigs()[0])
		if !strings.Contains(instruction, "[あと 30 秒で電話を終えます]") {
			t.Errorf("システム指示の締めの合図が --wrap-up-before と違う:\n%s", instruction)
		}

		// 呼び出しに 1 分使う。締めの合図は受話器が上がってから測るので、まだ送らない。
		s.advance(t, c, time.Minute)
		if c.hasEnded() {
			t.Fatalf("呼び出しの上限は 3 分なのに、1 分で電話が終わった: %v", c.err)
		}

		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")

		// 通話 30 秒。合図は通話が 1 分 30 秒になってからなので、まだ送らない。
		s.advance(t, c, 30*time.Second)
		if hasText(session, "[あと 30 秒で電話を終えます]") {
			t.Fatal("受話器を上げて 30 秒で締めの合図を送った")
		}

		s.clock.advance(time.Minute)
		waitForText(t, session, "[あと 30 秒で電話を終えます]")
		if c.hasEnded() {
			t.Fatal("締めの合図のときに電話が終わった")
		}

		s.clock.advance(30 * time.Second)
		if err := c.result(t); err != nil {
			t.Errorf("上限で電話が %v で終わった", err)
		}
		if !session.isClosed() {
			t.Error("上限で電話が終わっても Live API との接続を閉じていない")
		}
	})
}

func waitForText(t *testing.T, session *fakeSession, text string) genai.LiveClientContentInput {
	t.Helper()
	var found genai.LiveClientContentInput
	waitUntil(t, fmt.Sprintf("Gemini に %q を送らなかった", text), func() bool {
		in, ok := sentText(session, text)
		if ok {
			found = in
		}
		return ok
	})
	return found
}

func hasText(session *fakeSession, text string) bool {
	_, ok := sentText(session, text)
	return ok
}

func sentText(session *fakeSession, text string) (genai.LiveClientContentInput, bool) {
	for _, msg := range session.sent() {
		in, ok := msg.(genai.LiveClientContentInput)
		if !ok || len(in.Turns) != 1 || len(in.Turns[0].Parts) != 1 {
			continue
		}
		if in.Turns[0].Parts[0].Text == text {
			return in, true
		}
	}
	return genai.LiveClientContentInput{}, false
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
