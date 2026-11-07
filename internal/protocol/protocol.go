// Package protocol は、デバイスとバックエンドが両方で使う型と値を持つ。
package protocol

import (
	"fmt"
	"time"
)

// TokenPath は、電話を始めるときにデバイスが短命トークンをもらう、バックエンドのパスである。
// デバイスは何も入れずに POST する。
const TokenPath = "/token"

// GeminiAPIVersion は、短命トークンを作るときと、それで Live API につなぐときに使う API のバージョンである。
// Go の SDK では、短命トークンに v1alpha が要る。
const GeminiAPIVersion = "v1alpha"

// StartCue は、受話器が上がったことを AI に知らせる始まりの合図である。
// デバイスはこれを文字の発話として送り、AI はこれを受けて先に話す。
const StartCue = "[電話がつながりました]"

// WrapUpCue は、電話の長さの上限の lead 前に AI へ送る締めの合図である。
// 合図の中の時間は lead から作る。lead が 1 分なら「[あと 1 分で電話を終えます]」。
func WrapUpCue(lead time.Duration) string {
	return fmt.Sprintf("[あと %sで電話を終えます]", DurationWords(lead))
}

// DurationWords は、時間の長さを日本語で書く。「1 分」「30 秒」「1 分 30 秒」。
func DurationWords(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	d = d.Round(time.Second)
	minutes := d / time.Minute
	seconds := (d % time.Minute) / time.Second
	switch {
	case minutes > 0 && seconds == 0:
		return fmt.Sprintf("%d 分", minutes)
	case minutes > 0:
		return fmt.Sprintf("%d 分 %d 秒", minutes, seconds)
	default:
		return fmt.Sprintf("%d 秒", seconds)
	}
}

// CallTimes は、1 回の電話の時間の値である。
type CallTimes struct {
	// RingTimeout は呼び出しの上限である。
	RingTimeout time.Duration `json:"ringTimeout"`
	// MaxCall は電話の長さの上限である。受話器が上がってから測る。
	MaxCall time.Duration `json:"maxCall"`
	// WrapUpBefore は、締めの合図を電話の長さの上限のどれだけ前に送るかである。
	WrapUpBefore time.Duration `json:"wrapUpBefore"`
}

// TokenResponse は、TokenPath のレスポンスである。
type TokenResponse struct {
	// Token は、1 回だけ使える短命トークンである。Live API への接続で API キーの代わりに使う。
	Token string `json:"token"`
	// Model は、トークンに固定した Live API のモデルである。
	Model string `json:"model"`
	// Times は、この電話の時間の値である。
	Times CallTimes `json:"times"`
}
