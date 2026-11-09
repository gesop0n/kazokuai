package main

import (
	"time"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

const (
	samplePersonName = "田中 ハナ"
	sampleCallName   = "ハナさん"
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
	quote := point{}
	if len(c.points) > 0 {
		quote = c.points[0]
	}
	return map[string]any{
		"state":        protocol.StateEnded,
		"createdAt":    c.at,
		"startedAt":    c.at,
		"durationMs":   c.durationMs,
		"summaryState": "作れた",
		"summary": map[string]any{
			"headline": c.headline,
			"quote":    map[string]any{"text": quote.text, "offsetMs": quote.offsetMs},
			"meal":     c.meal.fields(),
			"sleep":    c.sleep.fields(),
			"health":   c.health.fields(),
			"topic":    c.topic,
			"points":   points,
		},
	}
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

func at(year int, month time.Month, day, hour, minute int) time.Time {
	return time.Date(year, month, day, hour, minute, 0, 0, japan)
}

func minutes(n int64) int64 { return n * 60 * 1000 }

// sampleCalls は、モックの通話記録に近い 1 週間である。出なかった電話を 1 件含む。
// 11 月 5 日の朝は、ホームのまとめと、詳細の会話である。
func sampleCalls() []sampleCall {
	return []sampleCall{
		{
			id: "20261031-0900", at: at(2026, 10, 31, 9, 0), durationMs: minutes(22),
			headline: "庭の菊が咲き始めた話をした", topic: "話し相手",
			meal: silent(), sleep: silent(), health: silent(),
			points: []point{{text: "庭の菊が咲き始めた話をした", offsetMs: 20000}},
			lines: []line{
				{protocol.SpeakerAI, 0, "ハナさん、おはようございます。庭はいかがですか。"},
				{protocol.SpeakerWatched, 20000, "庭の菊が咲き始めたよ。"},
			},
		},
		{
			id: "20261101-1200", at: at(2026, 11, 1, 12, 0), durationMs: minutes(31),
			headline: "お米が残り少ないと相談があった", topic: "話し相手",
			meal: silent(), sleep: silent(), health: silent(),
			points: []point{{text: "お米が残り少ないと相談があった", offsetMs: 15000}},
			lines: []line{
				{protocol.SpeakerAI, 0, "ハナさん、こんにちは。ごはんは足りていますか。"},
				{protocol.SpeakerWatched, 15000, "お米が残り少ないの。"},
			},
		},
		{
			id: "20261102-0900", at: at(2026, 11, 2, 9, 0), missed: true,
		},
		{
			id: "20261103-0900", at: at(2026, 11, 3, 9, 0), durationMs: minutes(18),
			headline: "お孫さんの運動会の話がはずんだ", topic: "話し相手",
			meal: silent(), sleep: silent(), health: silent(),
			points: []point{{text: "お孫さんの運動会の話がはずんだ", offsetMs: 12000}},
			lines: []line{
				{protocol.SpeakerAI, 0, "ハナさん、おはようございます。"},
				{protocol.SpeakerWatched, 12000, "お孫さんの運動会の話でね、はずんだの。"},
			},
		},
		{
			id: "20261104-1200", at: at(2026, 11, 4, 12, 0), durationMs: minutes(9),
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
			id: "20261104-1900", at: at(2026, 11, 4, 19, 0), durationMs: minutes(3),
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
			id: "20261105-0902", at: at(2026, 11, 5, 9, 2), durationMs: 6*60*1000 + 12*1000,
			headline: "朝ごはんを食べ、薬も飲んだそうです。膝の痛みを少し気にしています。",
			topic:    "体調",
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
			},
		},
	}
}
