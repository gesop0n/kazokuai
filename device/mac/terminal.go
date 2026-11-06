package mac

import (
	"bufio"
	"fmt"
	"io"

	"github.com/gesop0n/kazokuai/device/phone"
)

// Hook は Enter キーのフックである。Enter を押すたびに、受話器を上げる、置くを繰り返す。
type Hook struct {
	events chan phone.HookEvent
}

// NewHook は、in から 1 行読むたびに受話器を上げ下げし、そのことを out に書く。
func NewHook(in io.Reader, out io.Writer) *Hook {
	h := &Hook{events: make(chan phone.HookEvent)}
	go func() {
		lines := bufio.NewScanner(in)
		up := false
		for lines.Scan() {
			up = !up
			if up {
				fmt.Fprintln(out, "受話器を上げました。Enter で受話器を置きます。")
				h.events <- phone.PickedUp
			} else {
				fmt.Fprintln(out, "受話器を置きました。")
				h.events <- phone.PutDown
			}
		}
	}()
	return h
}

func (h *Hook) Events() <-chan phone.HookEvent { return h.events }

// Ringer は、呼び出し音の代わりにターミナルに文字を出す。音は鳴らさない。
type Ringer struct {
	Out io.Writer
}

func (r Ringer) Ring() {
	fmt.Fprintln(r.Out, "呼び出し中です。Enter で受話器を上げます。")
}

func (r Ringer) Stop() {
	fmt.Fprintln(r.Out, "呼び出しが止まりました。")
}

// Lamp は、ランプの代わりにターミナルに文字を出す。
type Lamp struct {
	Out io.Writer
}

func (l Lamp) On()  { fmt.Fprintln(l.Out, "ランプが点きました。") }
func (l Lamp) Off() { fmt.Fprintln(l.Out, "ランプが消えました。") }
