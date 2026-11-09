package pi

import (
	"fmt"
	"io"

	"github.com/gesop0n/kazokuai/device/phone"
)

// Lamp は、電話機にランプが無いので、点いたことと消えたことをログに書く。
type Lamp struct {
	Out io.Writer
}

func (l Lamp) On()  { fmt.Fprintln(l.Out, "ランプが点きました。") }
func (l Lamp) Off() { fmt.Fprintln(l.Out, "ランプが消えました。") }

// Ringer は、呼び出し音の ticket までは音を出さず、呼び出しと停止をログに書く。
type Ringer struct {
	Out io.Writer
}

func (r Ringer) Ring() { fmt.Fprintln(r.Out, "呼び出し中です。") }
func (r Ringer) Stop() { fmt.Fprintln(r.Out, "呼び出しが止まりました。") }

var (
	_ phone.Hook   = (*Hook)(nil)
	_ phone.Lamp   = Lamp{}
	_ phone.Ringer = Ringer{}
)
