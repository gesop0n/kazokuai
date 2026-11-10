// Package phone は、電話機をバックエンドにつなぎ続け、来た指示ごとに電話を進める。
// 電話の最中でないあいだは、フックとキーパッドを見る。受話器が上がっているときの「＃」で認証コードを読み上げ、
// そのとき「＊」で、鳴らさずに AI と話し始める。
//
// 電話機のハードウェア(受話器の音声、フック、キーパッド、呼び出し音、ランプ)と Gemini は、
// この package のインターフェースの後ろに置く。Mac とラズパイで実装を差し替える。
package phone

import (
	"context"

	"google.golang.org/genai"

	"github.com/gesop0n/kazokuai/internal/clock"
)

// 受話器の音声の速さ(Hz)である。どちらも 16 ビット、モノラル、リトルエンディアンの PCM で、
// Live API が決めている。
const (
	// MicSampleRate は、Live API に送るマイクの音の速さである。
	MicSampleRate = 16000
	// SpeakerSampleRate は、Live API から届く AI の音声の速さである。
	SpeakerSampleRate = 24000
)

// Handset は受話器の音声である。
type Handset interface {
	// Listen はマイクを開き、ctx が終わるまで、マイクの音を MicSampleRate の PCM で流す。
	// ctx が終わると、マイクを閉じてチャネルを閉じる。
	Listen(ctx context.Context) (<-chan []byte, error)
	// Play は、SpeakerSampleRate の PCM を、受話器のスピーカーで流す順番に並べる。
	Play(pcm []byte)
	// Hush は、まだ流していない音を捨てる。見守る方が AI の話に割って入ったときに使う。
	Hush()
}

// HookEvent は、受話器が上がったか置かれたかである。
type HookEvent int

const (
	PickedUp HookEvent = iota + 1
	PutDown
)

// Hook は、受話器を上げ下げしたことを知らせる。
// Prepare から Rest までが 1 回の監視で、その切れ目に押した Enter は次の監視へ持ち越さない。
// すでに上がっている受話器は、上がった出来事にはしない。置いた変化は伝える。Lifted が今の状態である。
type Hook interface {
	// Prepare は、受話器を下ろした状態から、この電話の上げ下げを知らせ始める。
	Prepare()
	// Rest は、この電話の上げ下げを知らせるのをやめる。
	Rest()
	Events() <-chan HookEvent
	// Lifted は、受話器が今上がっているかである。
	// 監視を切り替えるときに、電話機がこれを読んで覚え直す。
	Lifted() bool
}

// Ringer は呼び出し音である。
type Ringer interface {
	Ring()
	Stop()
}

// Lamp は電話機のランプである。電話の間は点く。
type Lamp interface {
	On()
	Off()
}

// Keypad は、押されたキーを 1 つずつ知らせる。
// 受話器が上がっていて電話の最中でないときの「＃」で認証コードを頼み、「＊」で AI と話し始める。
type Keypad interface {
	Keys() <-chan string
}

// Phone は電話機である。
type Phone struct {
	Handset Handset
	Hook    Hook
	Keypad  Keypad
	Ringer  Ringer
	Lamp    Lamp
}

// Clock は、呼び出しの上限、電話の長さ、つなぎ直す間隔、ping の間隔を測る時計である。
// テストは偽の時計を渡し、待たずに時刻を進める。
type Clock = clock.Clock

// Timer は、時間が経ったことを 1 回知らせる。
type Timer = clock.Timer

// Gemini は、短命トークンで Live API のセッションを開く。
type Gemini interface {
	Connect(ctx context.Context, token, model string) (Session, error)
}

// Session は Live API のセッションである。*genai.Session がこれを満たす。
type Session interface {
	SendClientContent(input genai.LiveClientContentInput) error
	SendRealtimeInput(input genai.LiveRealtimeInput) error
	Receive() (*genai.LiveServerMessage, error)
	Close() error
}
