// Package phone は、電話機で 1 回の電話を初めから終わりまで進める。
//
// 電話機のハードウェア(受話器の音声、フック、呼び出し音、ランプ)と Gemini は、
// この package のインターフェースの後ろに置く。Mac とラズパイで実装を差し替える。
package phone

import (
	"context"

	"google.golang.org/genai"
)

// Handset は受話器の音声である。
type Handset interface {
	// Listen はマイクを開き、ctx が終わるまで、マイクの音を 16 kHz、16 ビット、モノラルの PCM で流す。
	// ctx が終わると、マイクを閉じてチャネルを閉じる。
	Listen(ctx context.Context) (<-chan []byte, error)
	// Play は、24 kHz、16 ビット、モノラルの PCM を、受話器のスピーカーで流す順番に並べる。
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
type Hook interface {
	Events() <-chan HookEvent
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

// Phone は電話機である。
type Phone struct {
	Handset Handset
	Hook    Hook
	Ringer  Ringer
	Lamp    Lamp
}

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
