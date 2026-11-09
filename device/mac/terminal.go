package mac

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"sync"

	"github.com/gesop0n/kazokuai/device/phone"
)

// Hook は Enter キーのフックである。
// 電話のたびに受話器を下ろした状態から始め、待っているあいだの Enter は次の電話に持ち越さない。
type Hook struct {
	out     io.Writer
	events  chan phone.HookEvent
	presses chan struct{}

	mu     sync.Mutex
	cancel context.CancelFunc
	up     bool
}

// NewHook は、in の 1 行を Enter として受ける。上げたときと置いたときを out に書く。
// 上げ下げを知らせるのは、Prepare から Rest までのあいだだけである。
func NewHook(in io.Reader, out io.Writer) *Hook {
	h := &Hook{
		out:     out,
		events:  make(chan phone.HookEvent),
		presses: make(chan struct{}, 1),
	}
	go func() {
		lines := bufio.NewScanner(in)
		for lines.Scan() {
			// 1 つ残っているあいだの Enter は捨てる。呼び出しの前に押した分を、あとで受話器上げにしない。
			select {
			case h.presses <- struct{}{}:
			default:
			}
		}
	}()
	return h
}

// Prepare は、受話器を下ろした状態からこの電話の上げ下げを知らせ始める。
// 待っていた Enter は捨てるので、次の電話には出ない。
func (h *Hook) Prepare() {
	h.Rest()
	select {
	case <-h.presses:
	default:
	}
	ctx, cancel := context.WithCancel(context.Background())
	h.mu.Lock()
	h.cancel = cancel
	h.up = false
	h.mu.Unlock()
	go h.watch(ctx)
}

// Rest は、この電話の上げ下げを知らせるのをやめる。
func (h *Hook) Rest() {
	h.mu.Lock()
	cancel := h.cancel
	h.cancel = nil
	h.up = false
	h.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	// 前の電話の上げ下げが、次の電話のループに残らないように 1 つ捨てる。
	select {
	case <-h.events:
	default:
	}
}

func (h *Hook) watch(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-h.presses:
		}
		h.mu.Lock()
		if ctx.Err() != nil {
			h.mu.Unlock()
			return
		}
		h.up = !h.up
		up := h.up
		h.mu.Unlock()
		line := "受話器を置きました。"
		event := phone.PutDown
		if up {
			line = "受話器を上げました。Enter で受話器を置きます。"
			event = phone.PickedUp
		}
		fmt.Fprintln(h.out, line)
		select {
		case <-ctx.Done():
			return
		case h.events <- event:
		}
	}
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
