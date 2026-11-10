package server

import (
	"fmt"
	"strings"
	"time"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// japan は日本時間である。日本には夏時間がないので、tzdata がなくても使えるように固定の時差で持つ。
var japan = time.FixedZone("JST", 9*60*60)

var weekdays = [...]string{"日", "月", "火", "水", "木", "金", "土"}

// systemInstruction は、AI に渡すシステム指示を日本語で書く。
// script があり、見守る方から始めていない電話は伝言がある。通話内容を電話の早いうちにその言葉のまま伝え、返答を聞くよう書く。
// 見守る方からの電話は、通話内容のとおりに挨拶してから、話し相手として話すよう書く。伝言としては伝えない。
func systemInstruction(config Config, person watchedPerson, now time.Time, script string, fromWatched bool) string {
	now = now.In(japan)
	intro := "電話の相手のご家族に頼まれて、電話の相手に電話をかけています。"
	purpose := `- はじめに、相手の体調と今日の様子を軽く聞いてください。
- そのあとは、相手の話し相手になってください。
- 健康の話題は、相手の様子を聞くためだけに使ってください。体調について判断したり、助言したりしないでください。`
	start := fmt.Sprintf("「%s」を受け取ったら、電話がつながったところです。相手を「%s」と呼んで挨拶し、ご家族に頼まれて電話をかけたかぞくAIだと名乗ってください。", protocol.StartCue, person.CallName)
	if fromWatched {
		intro = "電話の相手が、受話器を上げて話し始めました。"
		purpose = strings.TrimSpace(script) + `
- 健康の話題は、相手の様子を聞くためだけに使ってください。体調について判断したり、助言したりしないでください。`
		start = fmt.Sprintf("「%s」を受け取ったら、電話がつながったところです。相手を「%s」と呼んで挨拶し、かぞくAIであることを伝えて、何を話したいかを尋ねてください。そのあとは、話し相手として話してください。", protocol.StartCue, person.CallName)
	} else if script = strings.TrimSpace(script); script != "" {
		// 通話内容は家族が入れた文なので、書式の動詞には渡さない。
		purpose = `- 電話の早いうちに、挨拶のあとすぐ、次の通話内容をその言葉のまま伝えてください。
- 伝えたあとは、相手の返答を聞いてください。
- 健康の話題は、相手の様子を聞くためだけに使ってください。体調について判断したり、助言したりしないでください。

# 通話内容
` + script
	}
	return fmt.Sprintf(`あなたは「かぞくAI」という名前の AI です。人ではありません。
%s

# 電話の相手
- お名前: %s
- 呼び方: %s

# 今の日時
%d年%d月%d日(%s) %d時%d分(日本時間)です。挨拶は、この時間帯に合わせてください。

# 話し方
- やさしい敬語で、ゆっくり話してください。
- 短い文で話してください。
- 一度に聞くことは 1 つだけにしてください。
- 相手が話している間は、割り込まずに待ってください。
- 聞き返されたら、同じ内容をもう一度言ってください。

# この電話の目的
%s

# 電話の始まり
%s

# 電話の終わり
「%s」を受け取ったら、話をまとめて、別れの挨拶をしてください。
`,
		intro,
		person.Name, person.CallName,
		now.Year(), now.Month(), now.Day(), weekdays[now.Weekday()], now.Hour(), now.Minute(),
		purpose,
		start,
		protocol.WrapUpCue(config.WrapUpBefore),
	)
}
