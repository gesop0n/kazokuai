package phone_test

import (
	"errors"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"
)

func TestSummary(t *testing.T) {
	const made = `{
		"headline": "朝ごはんを食べたそうです。",
		"quote": {"text": "「朝ごはんも食べたしね。」", "offsetMs": 10000},
		"meal": {"status": "話した", "said": "朝ごはんを食べた", "quote": "朝ごはんも食べたしね。", "concerning": false},
		"sleep": {"status": "話していない", "said": "", "quote": "", "concerning": false},
		"health": {"status": "話していない", "said": "", "quote": "", "concerning": false},
		"topic": "体調",
		"points": [{"text": "朝ごはんを食べた", "offsetMs": 10000}]
	}`

	t.Run("報告を受けるとすぐに電話を残し、そのあと偽の Gemini のまとめを書く", func(t *testing.T) {
		started := time.Date(2026, 11, 7, 8, 0, 0, 0, time.UTC)
		config := hanako
		config.SummaryModel = "gemini-3.6-flash"
		s := newSystem(t, config, started)
		s.gemini.holdSummary()
		t.Cleanup(s.gemini.releaseSummary)
		s.gemini.setSummary(summaryResponse(made))
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")
		session.reply(finished(inputTranscription("朝ごはんも食べたしね。")))
		s.terminal.waitForLines(t, "見守る方: 朝ごはんも食べたしね。")
		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatalf("受話器を置いたのに、電話が %v で終わった", err)
		}

		waitUntil(t, "まとめの generateContent が届かなかった", func() bool {
			return len(s.gemini.summaryRequests()) >= 1
		})
		call := waitCall(t, started)
		if _, ok := call.Data()["summaryState"]; ok {
			t.Fatal("Gemini が答える前に、まとめが書いてある")
		}

		s.gemini.releaseSummary()

		data := waitSummary(t, started)
		if data["summaryState"] != "作れた" {
			t.Fatalf("まとめの状態 = %v, want 作れた", data["summaryState"])
		}
		summary := objectField(t, data, "summary")
		if summary["headline"] != "朝ごはんを食べたそうです。" {
			t.Errorf("一言のまとめ = %v", summary["headline"])
		}
		if summary["topic"] != "体調" {
			t.Errorf("話の種類 = %v, want 体調", summary["topic"])
		}
		quote := objectField(t, summary, "quote")
		if quote["text"] != "「朝ごはんも食べたしね。」" {
			t.Errorf("本人の言葉 = %v", quote["text"])
		}
		meal := objectField(t, summary, "meal")
		if meal["status"] != "話した" || meal["quote"] != "朝ごはんも食べたしね。" {
			t.Errorf("食事 = %v", meal)
		}
		if objectField(t, summary, "sleep")["status"] != "話していない" {
			t.Errorf("睡眠 = %v", summary["sleep"])
		}
		points, ok := summary["points"].([]any)
		if !ok || len(points) != 1 {
			t.Fatalf("詳細 = %v, want 1 件", summary["points"])
		}
		point, ok := points[0].(map[string]any)
		if !ok || point["text"] != "朝ごはんを食べた" || intField(t, point, "offsetMs") != 10_000 {
			t.Errorf("詳細[0] = %v, want 朝ごはんを食べた の 10000 ミリ秒", point)
		}

		req := s.gemini.summaryRequests()[0]
		if req.model != "gemini-3.6-flash" {
			t.Errorf("まとめのモデル = %q, want gemini-3.6-flash", req.model)
		}
		if req.config == nil || req.config.ResponseMIMEType != "application/json" {
			t.Fatalf("応答の形式 = %+v, want application/json", req.config)
		}
		assertSummarySchema(t, req.config.ResponseJsonSchema)
		instruction := contentText(req.config.SystemInstruction)
		for _, want := range []string{"一字一句", "困っている", "いつもと違う", "医学的な判断はしない", "話していない"} {
			if !strings.Contains(instruction, want) {
				t.Errorf("Gemini への指示に %q がない:\n%s", want, instruction)
			}
		}
		if !strings.Contains(contentText(req.contents[0]), "朝ごはんも食べたしね。") {
			t.Errorf("Gemini に送った会話に、見守る方の発話がない:\n%s", contentText(req.contents[0]))
		}
	})

	t.Run("見守る方の発話にない本人の言葉は捨てる", func(t *testing.T) {
		started := time.Date(2026, 11, 7, 9, 0, 0, 0, time.UTC)
		s := newSystem(t, hanako, started)
		s.gemini.setSummary(summaryResponse(`{
			"headline": "朝ごはんを食べたそうです。",
			"quote": {"text": "「朝ごはんも食べたしね。」", "offsetMs": 0},
			"meal": {"status": "話した", "said": "朝ごはんを食べた", "quote": "  朝ごはんも食べたしね。  ", "concerning": false},
			"sleep": {"status": "話した", "said": "よく眠れた", "quote": "それはよかったです。", "concerning": false},
			"health": {"status": "話した", "said": "膝が痛い", "quote": "膝が痛くて歩けない", "concerning": true},
			"topic": "体調",
			"points": []
		}`))
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")
		session.reply(
			finished(inputTranscription("朝ごはんも食べたしね。")),
			finished(outputTranscription("それはよかったです。")),
		)
		s.terminal.waitForLines(t, "見守る方: 朝ごはんも食べたしね。", "かぞくAI: それはよかったです。")
		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatal(err)
		}

		summary := objectField(t, waitSummary(t, started), "summary")
		if objectField(t, summary, "quote")["text"] != "「朝ごはんも食べたしね。」" {
			t.Errorf("一致する本人の言葉 = %v", summary["quote"])
		}
		meal := objectField(t, summary, "meal")
		if meal["quote"] != "  朝ごはんも食べたしね。  " {
			t.Errorf("食事の本人の言葉 = %v, want 空白ごと残す", meal["quote"])
		}
		sleep := objectField(t, summary, "sleep")
		if sleep["quote"] != "" || sleep["said"] != "よく眠れた" {
			t.Errorf("睡眠 = %v, want AI の言葉は捨て、話した様子は残す", sleep)
		}
		health := objectField(t, summary, "health")
		if health["quote"] != "" || health["concerning"] != true || health["said"] != "膝が痛い" {
			t.Errorf("体調 = %v, want 一致しない本人の言葉だけを空にする", health)
		}
	})

	t.Run("generateContent が 3 回失敗すると、まとめを作れなかったと記録する", func(t *testing.T) {
		started := time.Date(2026, 11, 7, 10, 0, 0, 0, time.UTC)
		config := hanako
		config.SummaryRetryWait = time.Millisecond
		s := newSystem(t, config, started)
		s.gemini.failSummary(errors.New("gemini が 503 を返した"))
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")
		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatal(err)
		}

		data := waitSummary(t, started)
		if data["summaryState"] != "作れなかった" {
			t.Errorf("まとめの状態 = %v, want 作れなかった", data["summaryState"])
		}
		if _, ok := data["summary"]; ok {
			t.Errorf("失敗したのにまとめがある: %v", data["summary"])
		}
		if got := len(s.gemini.summaryRequests()); got != 3 {
			t.Errorf("generateContent を %d 回呼んだ, want 3", got)
		}
	})

	t.Run("伝言のある電話のまとめは、伝えたことと、発話にある返答を残す", func(t *testing.T) {
		started := time.Date(2026, 11, 7, 11, 0, 0, 0, time.UTC)
		s := newSystem(t, hanako, started)
		s.gemini.setSummary(summaryResponse(`{
			"headline": "伝言を伝えたそうです。",
			"quote": {"text": "", "offsetMs": 0},
			"meal": {"status": "話していない", "said": "", "quote": "", "concerning": false},
			"sleep": {"status": "話していない", "said": "", "quote": "", "concerning": false},
			"health": {"status": "話していない", "said": "", "quote": "", "concerning": false},
			"topic": "話し相手",
			"points": [],
			"told": "金曜の通院は、朝10時にお迎えに来る",
			"reply": {"text": "  わかったよ。玄関で待ってるね。  ", "offsetMs": 87000}
		}`))
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")
		session.reply(finished(inputTranscription("わかったよ。玄関で待ってるね。")))
		s.terminal.waitForLines(t, "見守る方: わかったよ。玄関で待ってるね。")
		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatal(err)
		}

		summary := objectField(t, waitSummary(t, started), "summary")
		if summary["told"] != "金曜の通院は、朝10時にお迎えに来る" {
			t.Errorf("伝えたこと = %v", summary["told"])
		}
		reply := objectField(t, summary, "reply")
		if reply["text"] != "  わかったよ。玄関で待ってるね。  " {
			t.Errorf("返答 = %v, want 空白ごと残す", reply["text"])
		}
		if intField(t, reply, "offsetMs") != 87_000 {
			t.Errorf("返答の時刻 = %v, want 87000 ミリ秒", reply["offsetMs"])
		}

		req := s.gemini.summaryRequests()[0]
		sent := contentText(req.contents[0])
		for _, want := range []string{testMessage, testScript, "わかったよ。玄関で待ってるね。"} {
			if !strings.Contains(sent, want) {
				t.Errorf("Gemini に送った会話に %q がない:\n%s", want, sent)
			}
		}
		instruction := contentText(req.config.SystemInstruction)
		for _, want := range []string{"伝えたこと", "返答", "一字一句"} {
			if !strings.Contains(instruction, want) {
				t.Errorf("Gemini への指示に %q がない:\n%s", want, instruction)
			}
		}
		props, _ := req.config.ResponseJsonSchema.(map[string]any)["properties"].(map[string]any)
		for _, name := range []string{"told", "reply"} {
			if _, ok := props[name]; !ok {
				t.Errorf("まとめの schema に %s がない", name)
			}
		}
	})

	t.Run("見守る方の発話にない返答は捨てる", func(t *testing.T) {
		started := time.Date(2026, 11, 7, 12, 0, 0, 0, time.UTC)
		s := newSystem(t, hanako, started)
		s.gemini.setSummary(summaryResponse(`{
			"headline": "伝言を伝えたそうです。",
			"quote": {"text": "「朝ごはんも食べたしね。」", "offsetMs": 0},
			"meal": {"status": "話していない", "said": "", "quote": "", "concerning": false},
			"sleep": {"status": "話していない", "said": "", "quote": "", "concerning": false},
			"health": {"status": "話していない", "said": "", "quote": "", "concerning": false},
			"topic": "話し相手",
			"points": [],
			"told": "金曜の通院は、朝10時にお迎えに来る",
			"reply": {"text": "それはよかったです。", "offsetMs": 5000}
		}`))
		c := s.startCall(t)
		session := s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		waitForText(t, session, "[電話がつながりました]")
		session.reply(
			finished(inputTranscription("朝ごはんも食べたしね。")),
			finished(outputTranscription("それはよかったです。")),
		)
		s.terminal.waitForLines(t, "見守る方: 朝ごはんも食べたしね。", "かぞくAI: それはよかったです。")
		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatal(err)
		}

		summary := objectField(t, waitSummary(t, started), "summary")
		reply := objectField(t, summary, "reply")
		if reply["text"] != "" {
			t.Errorf("返答 = %v, want AI の言葉は捨てる", reply["text"])
		}
		if summary["told"] != "金曜の通院は、朝10時にお迎えに来る" {
			t.Errorf("伝えたこと = %v, want 返答を捨てても残す", summary["told"])
		}
		if objectField(t, summary, "quote")["text"] != "「朝ごはんも食べたしね。」" {
			t.Errorf("本人の言葉 = %v", summary["quote"])
		}
	})
}

func TestReportSendFailure(t *testing.T) {
	t.Run("報告を送れなかったときは、ターミナルに理由を出して、送り直さない", func(t *testing.T) {
		started := time.Date(2026, 11, 7, 11, 0, 0, 0, time.UTC)
		s := newSystem(t, hanako, started)
		c := s.startCall(t)
		s.gemini.waitForSession(t, 1)
		s.phone.pickUp()
		before := len(callsOf(t))

		s.backend.Close()
		s.phone.putDown()
		if err := c.result(t); err != nil {
			t.Fatalf("報告の失敗で電話が %v で終わった", err)
		}

		waitUntil(t, "ターミナルに報告の失敗が出なかった", func() bool {
			return strings.Contains(s.terminal.text(), "電話の報告を送れなかった")
		})
		if got := strings.Count(s.terminal.text(), "電話の報告を送れなかった"); got != 1 {
			t.Errorf("報告の失敗が %d 行出た, want 1", got)
		}
		if got := len(callsOf(t)); got != before {
			t.Errorf("電話の件数 = %d, want 送れていないので %d", got, before)
		}
	})
}

func waitSummary(t *testing.T, started time.Time) map[string]any {
	t.Helper()
	call := waitCall(t, started)
	var data map[string]any
	waitUntil(t, "まとめの状態が記録されなかった", func() bool {
		doc, err := call.Ref.Get(t.Context())
		if err != nil {
			return false
		}
		data = doc.Data()
		_, ok := data["summaryState"]
		return ok
	})
	return data
}

func assertSummarySchema(t *testing.T, schema any) {
	t.Helper()
	object, ok := schema.(map[string]any)
	if !ok {
		t.Fatalf("ResponseJsonSchema = %T, want オブジェクト", schema)
	}
	props, ok := object["properties"].(map[string]any)
	if !ok {
		t.Fatalf("schema の properties = %T", object["properties"])
	}
	for _, name := range []string{"headline", "quote", "meal", "sleep", "health", "topic", "points"} {
		if _, ok := props[name]; !ok {
			t.Errorf("まとめの schema に %s がない", name)
		}
	}
	topic, ok := props["topic"].(map[string]any)
	if !ok {
		t.Fatal("話の種類の schema がない")
	}
	got := map[string]bool{}
	switch values := topic["enum"].(type) {
	case []any:
		for _, value := range values {
			text, _ := value.(string)
			got[text] = true
		}
	case []string:
		for _, value := range values {
			got[value] = true
		}
	default:
		t.Fatalf("話の種類の enum = %T", topic["enum"])
	}
	for _, want := range []string{"体調", "話し相手", "操作案内"} {
		if !got[want] {
			t.Errorf("話の種類の enum = %v, want %s を含む", topic["enum"], want)
		}
	}
}

func contentText(content *genai.Content) string {
	if content == nil {
		return ""
	}
	var b strings.Builder
	for _, part := range content.Parts {
		b.WriteString(part.Text)
	}
	return b.String()
}

func objectField(t *testing.T, data map[string]any, name string) map[string]any {
	t.Helper()
	value, ok := data[name].(map[string]any)
	if !ok {
		t.Fatalf("%s = %T(%v), want オブジェクト", name, data[name], data[name])
	}
	return value
}
