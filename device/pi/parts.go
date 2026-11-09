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

var (
	_ phone.Hook = (*Hook)(nil)
	_ phone.Lamp = Lamp{}
)
