// Package protocol は、デバイスとバックエンドが両方で使う型と値を持つ。
package protocol

import (
	"fmt"
	"time"
)

// TokenPath は、電話を始めるときにデバイスが短命トークンをもらう、バックエンドのパスである。
// デバイスは TokenRequest を JSON で入れて POST し、PhoneSecretHeader に合言葉を付ける。
const TokenPath = "/token"

// PhonePath は、電話機がつなぎ続ける WebSocket のパスである。
// クエリ watchedPerson に、見守る方の ID を付ける。接続のときも PhoneSecretHeader に合言葉を付ける。
const PhonePath = "/phone"

// PhoneSecretHeader は、電話機が /token、/calls、WebSocket に付ける合言葉のヘッダーである。
const PhoneSecretHeader = "Kazokuai-Secret"

// DevPhoneSecret は、手元の demo- プロジェクトで、環境変数 PHONE_SECRET が無いときに使う合言葉である。
// 本番の合言葉は環境変数で渡し、リポジトリには置かない。
const DevPhoneSecret = "dev-phone-secret"

// PingInterval は、電話機とバックエンドが ping を送り合う間隔である。
const PingInterval = 30 * time.Second

// ReconnectGrace は、電話の最中に接続が切れてから、つながらなかったにするまでの時間である。
const ReconnectGrace = 30 * time.Second

// StartCallPath は、ログインした家族が今すぐ通話を始めるパスである。
// Authorization ヘッダーに家族の ID トークンを Bearer で入れ、本文に伝えたいことと通話内容を JSON で入れて POST する。
const StartCallPath = "/calls/now"

// DraftScriptPath は、ログインした家族が通話内容の案を頼むパスである。
// Authorization ヘッダーに家族の ID トークンを Bearer で入れ、本文に伝えたいことを JSON で入れて POST する。
// 呼び方は、その家族の見守る方から読む。Live API は使わない。
const DraftScriptPath = "/calls/script"

// PhoneNotConnected は、電話機がつながっていないので今すぐ通話を始められなかった、というエラーである。
// アプリはこれを見て「電話機につながっていません」と出す。
const PhoneNotConnected = "phone_not_connected"

// CallInProgress は、電話の最中なので今すぐ通話を始められなかった、というエラーである。
// アプリはこれを見て「通話中です」と出す。
const CallInProgress = "call_in_progress"

// WebSocket のメッセージの種類である。
const (
	// PhoneTypeCall は、バックエンドが電話機に送る、電話をかける指示である。
	PhoneTypeCall = "call"
	// PhoneTypeState は、電話機がバックエンドに送る、電話の状態である。
	PhoneTypeState = "state"
)

// 電話の状態である。電話機が変わるたびに送り、バックエンドが電話の文書に書く。
const (
	// StateRinging は呼び出し中である。
	StateRinging = "呼び出し中"
	// StateTalking は通話中である。
	StateTalking = "通話中"
	// StateEnded は、受話器が上がった電話が終わったときである。
	StateEnded = "終わった"
	// StateMissed は、見守る方が出なかったときである。
	StateMissed = "出なかった"
	// StateFailed は、電話が終わる前に電話機が失敗したか、接続が切れたときである。
	StateFailed = "つながらなかった"
)

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

// CallReportPath は、電話が終わったときにデバイスが報告を送る、バックエンドのパスである。
// 電話機は PhoneSecretHeader に合言葉を付ける。報告には、その電話の ID と見守る方の ID を付ける。
// バックエンドは 202 Accepted をすぐ返す。
const CallReportPath = "/calls"

// 発話の話した人である。
const (
	// SpeakerWatched は見守る方である。
	SpeakerWatched = "見守る方"
	// SpeakerAI は AI である。
	SpeakerAI = "AI"
)

// Utterance は、電話の中の 1 つの発話である。
type Utterance struct {
	// Speaker は、話した人である。SpeakerWatched か SpeakerAI。
	Speaker string `json:"speaker"`
	// OffsetMs は、受話器を上げてから、この発話が始まるまでのミリ秒である。
	OffsetMs int64 `json:"offsetMs"`
	// Text は、その発話の文字起こしである。
	Text string `json:"text"`
}

// CallReport は、受話器が上がった電話が終わったときの報告である。
type CallReport struct {
	// CallID は、この電話の ID である。
	CallID string `json:"callId"`
	// WatchedPersonID は、この電話の見守る方の ID である。
	WatchedPersonID string `json:"watchedPersonId"`
	// StartedAt は、受話器を上げた時刻である。
	StartedAt time.Time `json:"startedAt"`
	// DurationMs は、受話器を上げてから電話が終わるまでのミリ秒である。
	DurationMs int64 `json:"durationMs"`
	// Utterances は、始まった順の発話である。
	Utterances []Utterance `json:"utterances"`
}

// TokenRequest は、TokenPath にデバイスが送る本文である。
type TokenRequest struct {
	// CallID は、トークンをもらう電話の ID である。
	CallID string `json:"callId"`
	// WatchedPersonID は、その電話の見守る方の ID である。
	WatchedPersonID string `json:"watchedPersonId"`
}

// PhoneMessage は、電話機とバックエンドの WebSocket でやり取りする 1 通である。
type PhoneMessage struct {
	// Type は、PhoneTypeCall か PhoneTypeState である。
	Type string `json:"type"`
	// CallID は、このメッセージの電話の ID である。
	CallID string `json:"callId"`
	// State は、PhoneTypeState のときの電話の状態である。
	State string `json:"state,omitempty"`
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
