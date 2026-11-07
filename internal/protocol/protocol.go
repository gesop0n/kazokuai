// Package protocol は、デバイスとバックエンドが両方で使う型と値を持つ。
package protocol

// TokenPath は、電話を始めるときにデバイスが短命トークンをもらう、バックエンドのパスである。
// デバイスは何も入れずに POST する。
const TokenPath = "/token"

// GeminiAPIVersion は、短命トークンを作るときと、それで Live API につなぐときに使う API のバージョンである。
// Go の SDK では、短命トークンに v1alpha が要る。
const GeminiAPIVersion = "v1alpha"

// StartCue は、受話器が上がったことを AI に知らせる始まりの合図である。
// デバイスはこれを文字の発話として送り、AI はこれを受けて先に話す。
const StartCue = "[電話がつながりました]"

// TokenResponse は、TokenPath のレスポンスである。
type TokenResponse struct {
	// Token は、1 回だけ使える短命トークンである。Live API への接続で API キーの代わりに使う。
	Token string `json:"token"`
	// Model は、トークンに固定した Live API のモデルである。
	Model string `json:"model"`
}
