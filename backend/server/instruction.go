package server

import (
	"fmt"
	"time"

	"github.com/gesop0n/kazokuai/internal/protocol"
)

// japan は日本時間である。日本には夏時間がないので、tzdata がなくても使えるように固定の時差で持つ。
var japan = time.FixedZone("JST", 9*60*60)

var weekdays = [...]string{"日", "月", "火", "水", "木", "金", "土"}

// systemInstruction は、AI に渡すシステム指示を日本語で書く。
func systemInstruction(config Config, person watchedPerson, now time.Time) string {
	now = now.In(japan)
	return fmt.Sprintf(`あなたは「かぞくAI」という名前の AI です。人ではありません。
電話の相手のご家族に頼まれて、電話の相手に電話をかけています。

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
- はじめに、相手の体調と今日の様子を軽く聞いてください。
- そのあとは、相手の話し相手になってください。
- 健康の話題は、相手の様子を聞くためだけに使ってください。体調について判断したり、助言したりしないでください。

# 電話の始まり
「%s」を受け取ったら、電話がつながったところです。相手を「%s」と呼んで挨拶し、ご家族に頼まれて電話をかけたかぞくAIだと名乗ってください。

# 電話の終わり
「%s」を受け取ったら、話をまとめて、別れの挨拶をしてください。
`,
		person.Name, person.CallName,
		now.Year(), now.Month(), now.Day(), weekdays[now.Weekday()], now.Hour(), now.Minute(),
		protocol.StartCue, person.CallName,
		protocol.WrapUpCue(config.WrapUpBefore),
	)
}
