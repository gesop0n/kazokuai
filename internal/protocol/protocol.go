// Package protocol は、デバイスとバックエンドが両方で使う型と値を持つ。
package protocol

import (
	"fmt"
	"time"
)

// TokenPath は、電話を始めるときにデバイスが短命トークンをもらう、バックエンドのパスである。
// デバイスは TokenRequest を JSON で入れて POST し、PhoneIDHeader と PhoneKeyHeader を付ける。
// 見守る方は結び付きから決まる。
const TokenPath = "/token"

// PhonePath は、電話機がつなぎ続ける WebSocket のパスである。
// 電話機は PhoneIDHeader と PhoneKeyHeader を付ける。見守る方は結び付きから決まる。
// クエリ watchedPerson は受け付けない。
const PhonePath = "/phone"

// PhoneRegisterPath は、電話機が自分の ID と鍵を登録するパスである。/api の下には置かない。
// 電話機は PhoneIDHeader と PhoneKeyHeader に ID と鍵を付け、PhoneSecretHeader に合言葉を付ける。
const PhoneRegisterPath = "/phones"

// PhoneCodePath は、電話機が認証コードを頼むパスである。/api の下には置かない。
// 電話機は PhoneIDHeader と PhoneKeyHeader に ID と鍵を付ける。
const PhoneCodePath = "/phones/code"

// PhoneCallPath は、電話機が受話器を上げて「＊」を押したときに電話を始めるパスである。/api の下には置かない。
// 電話機は PhoneIDHeader と PhoneKeyHeader を付ける。トークンの道と同じ認証である。本文は空。答えは StartedCall。
const PhoneCallPath = "/phones/calls"

// StartedCall は、始めた電話の ID である。
// 電話機は、ほかの電話と同じく、これをトークンと報告に使う。
type StartedCall struct {
	ID string `json:"id"`
}

// PhoneSecretHeader は、電話機を登録するときの合言葉のヘッダーである。
const PhoneSecretHeader = "Kazokuai-Secret"

// PhoneIDHeader は、電話機が自分の ID を付けるヘッダーである。
const PhoneIDHeader = "Kazokuai-Phone-Id"

// PhoneKeyHeader は、電話機が自分の鍵を付けるヘッダーである。
const PhoneKeyHeader = "Kazokuai-Phone-Key"

// 電話機の認証で返す答えである。知らない ID と、鍵が違うときと、別の見守る方を名乗るときで、文を分ける。
const (
	// PhoneAnswerBadSecret は、合言葉が無い、または違うときである。
	PhoneAnswerBadSecret = "合言葉が違います"
	// PhoneAnswerUnknownPhone は、電話機の ID が登録されていないときである。
	PhoneAnswerUnknownPhone = "この電話機は登録されていません"
	// PhoneAnswerBadKey は、登録されている ID に対して鍵が違うときである。
	PhoneAnswerBadKey = "鍵が違います"
	// PhoneAnswerOtherPerson は、リクエストが名乗った見守る方が、結び付きと違うときである。
	PhoneAnswerOtherPerson = "別の見守る方の電話機ではありません"
	// PhoneAnswerSyncClosed は、同期済みの電話機が、その見守る方の家族が同期の準備を始めていないあいだに認証コードを頼んだときである。
	// 電話機は何も流さない。ほかのエラーとは文を分ける。
	PhoneAnswerSyncClosed = "同期の準備が始まっていません"
)

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

// SyncPreparePath は、ログインした家族が同期の準備を始めるパスである。/api の下にも置く。
// Authorization ヘッダーに家族の ID トークンを Bearer で入れて POST する。
// すでに始まっているときは、それを返し、新しいものとしては数えない。
const SyncPreparePath = "/sync"

// SyncCodePath は、ログインした家族が認証コードを送るパスである。/api の下にも置く。
// Authorization ヘッダーに家族の ID トークンを Bearer で入れ、本文に 6 桁の認証コードを JSON の code で入れて POST する。
const SyncCodePath = "/sync/code"

// PhoneNotConnected は、電話機がつながっていないので今すぐ通話を始められなかった、というエラーである。
// アプリはこれを見て「電話機につながっていません」と出す。
const PhoneNotConnected = "phone_not_connected"

// CallInProgress は、電話の最中なので今すぐ通話を始められなかった、というエラーである。
// アプリはこれを見て「通話中です」と出す。見守る方からの電話でも、呼び出し中か通話中なら同じ答えを返す。
const CallInProgress = "call_in_progress"

// PhoneNotSynced は、電話機が同期していないので、見守る方からの電話を始められなかった、というエラーである。
const PhoneNotSynced = "phone_not_synced"

// CallStartedByWatchedPerson は、電話の文書で、見守る方が「＊」で始めたことを示すフィールドである。
// 値が true の電話は、伝えたいことが空である。
const CallStartedByWatchedPerson = "startedByWatchedPerson"

// BookingPath は、ログインした家族が予約を保存するパスである。/api の下にも置く。
// Authorization ヘッダーに家族の ID トークンを Bearer で入れ、本文に BookingBody を JSON で入れて POST する。
// 予約を直すときは、同じ道のうしろに予約の ID を足して POST する。
const BookingPath = "/bookings"

// BookingTaskPath は、予約の時刻に Cloud Tasks が呼ぶパスである。/api の下には置かない。
// Authorization ヘッダーに、タスクのサービスアカウントの OIDC トークンを Bearer で入れる。
// audience はバックエンドの URL。本文は BookingTask。
// demo- のプロジェクトではこの道を閉じ、バックエンドの中のタイマーが同じ処理を呼ぶ。
const BookingTaskPath = "/tasks/bookings"

// 予約の保存と直しで、アプリが見分けるエラーである。本文の error に入る。
const (
	// BookingTooSoon は、時刻が今から 1 分より先ではないときである。
	BookingTooSoon = "booking_too_soon"
	// BookingTooFar は、時刻が今から 30 日より先のときである。
	BookingTooFar = "booking_too_far"
	// BookingTooClose は、同じ見守る方の別の予約が前後 10 分以内にあるときである。
	BookingTooClose = "booking_too_close"
	// BookingNotFound は、その予約が、その家族の見守る方の下にないときである。
	BookingNotFound = "booking_not_found"
	// BookingAlreadyCalled は、かけたあとの予約を直そうとしたときである。
	BookingAlreadyCalled = "booking_already_called"
)

// 同期でアプリが見分けるエラーである。本文の error に入る。
const (
	// SyncCodeWrong は、認証コードが違うときである。同期の準備はまだ続く。
	SyncCodeWrong = "sync_code_wrong"
	// SyncPrepEnded は、同期の準備が終わっているときである。切れたときと、5 回目の間違いを含む。
	SyncPrepEnded = "sync_prep_ended"
	// SyncPrepLimited は、1 時間に始めた同期の準備が 5 回を超えたときである。
	SyncPrepLimited = "sync_prep_limited"
)

// WebSocket のメッセージの種類である。
const (
	// PhoneTypeCall は、バックエンドが電話機に送る、電話をかける指示である。
	PhoneTypeCall = "call"
	// PhoneTypeState は、電話機がバックエンドに送る、電話の状態である。
	PhoneTypeState = "state"
	// PhoneTypeSynced は、バックエンドが電話機に送る、同期済みになったという知らせである。
	PhoneTypeSynced = "synced"
	// PhoneTypeNotSynced は、バックエンドが電話機に送る、同期していない電話機に戻ったという知らせである。
	// つないだときに、まだ同期していないことも、これで知らせる。
	PhoneTypeNotSynced = "not_synced"
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
// 電話機ごとの認証では PhoneIDHeader と PhoneKeyHeader を付ける。
// 古い道では PhoneSecretHeader に合言葉を付ける。
// 報告には、その電話の ID と見守る方の ID を付ける。名乗った見守る方が結び付きと違うときは断る。
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
	// 電話機は入れない。バックエンドが結び付きから決める。結び付きと違う ID は断る。
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
	// 電話機は入れない。バックエンドが結び付きから決める。結び付きと違う ID は断る。
	WatchedPersonID string `json:"watchedPersonId"`
}

// PhoneMessage は、電話機とバックエンドの WebSocket でやり取りする 1 通である。
type PhoneMessage struct {
	// Type は、PhoneTypeCall、PhoneTypeState、PhoneTypeSynced、PhoneTypeNotSynced のいずれかである。
	Type string `json:"type"`
	// CallID は、このメッセージの電話の ID である。
	CallID string `json:"callId"`
	// State は、PhoneTypeState のときの電話の状態である。
	State string `json:"state,omitempty"`
}

// BookingBody は、予約を保存するときと直すときの本文である。
// 予約は watchedPersons/{id}/bookings/{予約} に置く。
// フィールドは at（時刻）、message（伝えたいこと）、script（通話内容）、
// number（直すたびに 1 つ増える番号）、called（かけたかどうか）、callId（かけた電話）、
// sent（電話機に届け終えたか。家族の本文には無く、バックエンドだけが書く）、
// unknownCallId（送ったかどうかが分からない電話の ID。家族の本文には無く、バックエンドだけが書く）、
// sample（見本。demo:seed だけが true にする。タスクは作らない。家族が直すとバックエンドが外す）、
// taskPending（タスクがまだ Cloud Tasks に入っていないか。家族の本文には無く、バックエンドだけが書く。見本の予約は持たない）である。
type BookingBody struct {
	// At は、電話をかける時刻である。
	At time.Time `json:"at"`
	// Message は、家族が入れた伝えたいことである。
	Message string `json:"message"`
	// Script は、その電話で AI が話す通話内容である。
	Script string `json:"script"`
}

// BookingTask は、BookingTaskPath に Cloud Tasks が送る本文である。
// Number は、そのタスクを作ったときの予約の番号である。今の番号と違うときは、何もしない。
type BookingTask struct {
	// WatchedPersonID は、予約の見守る方の ID である。
	WatchedPersonID string `json:"watchedPersonId"`
	// BookingID は、予約の ID である。
	BookingID string `json:"bookingId"`
	// Number は、予約の番号である。
	Number int64 `json:"number"`
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
