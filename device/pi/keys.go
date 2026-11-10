package pi

import (
	"context"

	"github.com/gesop0n/kazokuai/device/phone"
)

// ListenKeys は、押されたキーを電話機へ渡す。
// ctx を取り消して done が戻ってから、パッドを閉じる。走査の途中で閉じない。
func ListenKeys(ctx context.Context, pad *Keypad) (phone.Keypad, func()) {
	keys := make(chan string, 1)
	done := make(chan struct{})
	go func() {
		defer close(done)
		defer close(keys)
		for {
			if err := ctx.Err(); err != nil {
				return
			}
			key, err := pad.ReadKey()
			if err != nil {
				return
			}
			if key != "" {
				select {
				case <-ctx.Done():
					return
				case keys <- key:
				}
			}
			timer := pad.clk.NewTimer(pad.pollEvery)
			select {
			case <-ctx.Done():
				timer.Stop()
				return
			case <-timer.Chan():
			}
		}
	}()
	return keyForward(keys), func() { <-done }
}

// keyForward は、ListenKeys が読む側へ渡すキーの口である。
type keyForward chan string

func (k keyForward) Keys() <-chan string { return k }

var _ phone.Keypad = keyForward(nil)
