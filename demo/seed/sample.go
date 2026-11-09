package main

import (
	"time"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

const (
	samplePersonName = "田中 ハナ"
	sampleCallName   = "ハナさん"
	// モックの伝言への返答。返答は、見守る方の発話と同じ文である。
	sampleMessage = "金曜の通院、10時に迎えに行くと伝えて"
	sampleScript  = "「ハナさん、美咲さんからご伝言です。\n金曜の通院は、朝10時に\nお迎えに来るそうです。」"
	sampleTold    = "金曜の通院は、朝10時にお迎えに来る"
	sampleReply   = "わかったよ。玄関で待ってるね。"
)

// japan は、見本の電話の時刻である。アプリは端末の現地時間で出す。
var japan = time.FixedZone("Asia/Tokyo", 9*60*60)

type sampleCall struct {
	id         string
	at         time.Time
	durationMs int64
	missed     bool
	headline   string
	topic      string
	meal       condition
	sleep      condition
	health     condition
	points     []point
	lines      []line
	// 伝言。伝えたいことと通話内容。無い電話は空。
	message string
	script  string
	// 伝えたことと、見守る方の発話にある返答。無い電話は空。
	told  string
	reply string
}

type condition struct {
	status     string
	said       string
	quote      string
	concerning bool
}

type point struct {
	text     string
	offsetMs int64
}

type line struct {
	speaker  string
	offsetMs int64
	text     string
}

func (c sampleCall) fields() map[string]any {
	if c.missed {
		return map[string]any{
			"state":     protocol.StateMissed,
			"createdAt": c.at,
		}
	}
	points := make([]map[string]any, len(c.points))
	for i, item := range c.points {
		points[i] = map[string]any{"text": item.text, "offsetMs": item.offsetMs}
	}
	// 本人の言葉は、見守る方の最初の発言をそのまま入れる。
	quote := firstWatched(c.lines)
	summary := map[string]any{
		"headline": c.headline,
		"quote":    map[string]any{"text": quote.text, "offsetMs": quote.offsetMs},
		"meal":     c.meal.fields(),
		"sleep":    c.sleep.fields(),
		"health":   c.health.fields(),
		"topic":    c.topic,
		"points":   points,
	}
	if c.told != "" || c.reply != "" {
		reply := watchedLine(c.lines, c.reply)
		summary["told"] = c.told
		summary["reply"] = map[string]any{"text": c.reply, "offsetMs": reply.offsetMs}
	}
	fields := map[string]any{
		"state":        protocol.StateEnded,
		"createdAt":    c.at,
		"startedAt":    c.at,
		"durationMs":   c.durationMs,
		"summaryState": "作れた",
		"summary":      summary,
	}
	if c.message != "" || c.script != "" {
		fields["message"] = c.message
		fields["script"] = c.script
	}
	return fields
}

func watchedLine(lines []line, text string) line {
	for _, item := range lines {
		if item.speaker == protocol.SpeakerWatched && item.text == text {
			return item
		}
	}
	return line{}
}

func firstWatched(lines []line) line {
	for _, item := range lines {
		if item.speaker == protocol.SpeakerWatched {
			return item
		}
	}
	return line{}
}

func (c condition) fields() map[string]any {
	return map[string]any{
		"status":     c.status,
		"said":       c.said,
		"quote":      c.quote,
		"concerning": c.concerning,
	}
}

func talked(said, quote string, concerning bool) condition {
	return condition{status: "話した", said: said, quote: quote, concerning: concerning}
}

func silent() condition {
	return condition{status: "話していない"}
}

func minutes(n int64) int64 { return n * 60 * 1000 }

func callID(at time.Time) string {
	return at.In(japan).Format("20060102-1504")
}

// sampleDay は、見本の 1 週間が朝で終わる日である。日付は日本時間。
func sampleDay(req Request) time.Time {
	day := req.Today
	if day.IsZero() {
		day = time.Now()
	}
	return day.In(japan)
}

// sampleCalls は、モックの通話記録に近い 1 週間である。出なかった電話を 1 件含む。
// day の朝で終わり、その朝の電話がホームのまとめと詳細の会話になる。
func sampleCalls(day time.Time) []sampleCall {
	y, m, d := day.In(japan).Date()
	at := func(delta, hour, minute int) time.Time {
		return time.Date(y, m, d+delta, hour, minute, 0, 0, japan)
	}
	fiveDaysAgo := at(-5, 9, 0)
	fourDaysAgo := at(-4, 12, 0)
	threeDaysAgo := at(-3, 9, 0)
	twoDaysAgo := at(-2, 9, 0)
	yesterdayNoon := at(-1, 12, 0)
	yesterdayNight := at(-1, 19, 0)
	thisMorning := at(0, 9, 2)
	return []sampleCall{
		{
			id: callID(fiveDaysAgo), at: fiveDaysAgo, durationMs: minutes(22),
			headline: "庭の菊が咲き始めた話をした", topic: "話し相手",
			meal: silent(), sleep: silent(), health: silent(),
			points: []point{{text: "庭の菊が咲き始めた話をした", offsetMs: 20000}},
			lines: []line{
				{protocol.SpeakerAI, 0, "ハナさん、おはようございます。庭はいかがですか。"},
				{protocol.SpeakerWatched, 20000, "庭の菊が咲き始めたよ。"},
			},
		},
		{
			id: callID(fourDaysAgo), at: fourDaysAgo, durationMs: minutes(31),
			headline: "お米が残り少ないと相談があった", topic: "話し相手",
			meal: silent(), sleep: silent(), health: silent(),
			points: []point{{text: "お米が残り少ないと相談があった", offsetMs: 15000}},
			lines: []line{
				{protocol.SpeakerAI, 0, "ハナさん、こんにちは。ごはんは足りていますか。"},
				{protocol.SpeakerWatched, 15000, "お米が残り少ないの。"},
			},
		},
		{
			id: callID(threeDaysAgo), at: threeDaysAgo, missed: true,
		},
		{
			id: callID(twoDaysAgo), at: twoDaysAgo, durationMs: minutes(18),
			headline: "お孫さんの運動会の話がはずんだ", topic: "話し相手",
			meal: silent(), sleep: silent(), health: silent(),
			points: []point{{text: "お孫さんの運動会の話がはずんだ", offsetMs: 12000}},
			lines: []line{
				{protocol.SpeakerAI, 0, "ハナさん、おはようございます。"},
				{protocol.SpeakerWatched, 12000, "お孫さんの運動会の話でね、はずんだの。"},
			},
		},
		{
			id: callID(yesterdayNoon), at: yesterdayNoon, durationMs: minutes(9),
			headline: "テレビの映し方を案内して解決", topic: "操作案内",
			meal: silent(), sleep: silent(), health: silent(),
			points: []point{{text: "テレビの映し方を案内して解決", offsetMs: 30000}},
			lines: []line{
				{protocol.SpeakerAI, 0, "ハナさん、こんにちは。テレビの映し方を一緒に見てみましょう。"},
				{protocol.SpeakerWatched, 8000, "映らないのよ。"},
				{protocol.SpeakerAI, 20000, "電源を入れ直してみてください。"},
				{protocol.SpeakerWatched, 30000, "映ったわ。テレビ、見られるようになった。"},
			},
		},
		{
			id: callID(yesterdayNight), at: yesterdayNight, durationMs: minutes(3),
			headline: "夕飯は大根の煮物。夜の薬も飲んだ", topic: "体調",
			meal:   talked("夜ごはんは大根の煮物", "大根の煮物を食べたよ", false),
			sleep:  silent(),
			health: talked("夜の薬を飲んだ", "夜の薬も飲んだよ", false),
			points: []point{{text: "夕飯は大根の煮物。夜の薬も飲んだ", offsetMs: 8000}},
			lines: []line{
				{protocol.SpeakerAI, 0, "ハナさん、こんばんは。夜のごはんは何を食べましたか。"},
				{protocol.SpeakerWatched, 8000, "大根の煮物を食べたよ。"},
				{protocol.SpeakerAI, 20000, "夜のお薬は飲みましたか。"},
				{protocol.SpeakerWatched, 32000, "夜の薬も飲んだよ。"},
			},
		},
		{
			id: callID(thisMorning), at: thisMorning, durationMs: 6*60*1000 + 12*1000,
			headline: "朝ごはんを食べ、薬も飲んだそうです。膝の痛みを少し気にしています。",
			topic:    "体調",
			message:  sampleMessage,
			script:   sampleScript,
			told:     sampleTold,
			reply:    sampleReply,
			meal:     talked("朝ごはんを食べた", "朝ごはんも食べたしね", false),
			sleep:    talked("よく眠れた", "よく眠れたよ", false),
			health:   talked("膝が痛い。階段がつらい", "昨日の夕方から膝が痛くてね", true),
			points: []point{
				{text: "朝ごはんを食べ、よく眠れたそうです", offsetMs: 11 * 1000},
				{text: "昨日の夕方から膝が痛く、階段がつらいそうです", offsetMs: 63 * 1000},
				{text: "朝の薬は飲んだと話しています", offsetMs: 4*60*1000 + 12*1000},
			},
			lines: []line{
				{protocol.SpeakerAI, 0, "おはようございます、ハナさん。昨夜はよく眠れましたか。"},
				{protocol.SpeakerWatched, 11 * 1000, "よく眠れたよ。朝ごはんも食べたしね。"},
				{protocol.SpeakerAI, 48 * 1000, "それは何よりです。お体の具合はいかがですか。"},
				{protocol.SpeakerWatched, 63 * 1000, "昨日の夕方から膝が痛くてね。階段がつらいの。"},
				{protocol.SpeakerAI, 2 * 60 * 1000, "それはおつらいですね。美咲さんにもお伝えしておきましょうか。"},
				{protocol.SpeakerWatched, 2*60*1000 + 21*1000, "そうね、お願いしようかな。"},
				{protocol.SpeakerAI, 4*60*1000 + 5*1000, "朝の薬は飲みましたか。"},
				{protocol.SpeakerWatched, 4*60*1000 + 12*1000, "飲んだよ。"},
				{protocol.SpeakerAI, 5 * 60 * 1000, "ハナさん、美咲さんからご伝言です。金曜の通院は、朝10時にお迎えに来るそうです。"},
				{protocol.SpeakerWatched, 5*60*1000 + 20*1000, sampleReply},
			},
		},
	}
}
