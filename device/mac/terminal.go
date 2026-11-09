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
	out    io.Writer
	events chan phone.HookEvent

	mu      sync.Mutex
	cond    *sync.Cond
	cancel  context.CancelFunc
	stopped chan struct{} // 今の監視が終わると閉じる
	up      bool
	pending bool // まだ上げ下げに使っていない Enter が 1 つある
}

// NewHook は、in の 1 行を Enter として受ける。上げたときと置いたときを out に書く。
// 上げ下げを知らせるのは、Prepare から Rest までのあいだだけである。
func NewHook(in io.Reader, out io.Writer) *Hook {
	h := &Hook{
		out:    out,
		events: make(chan phone.HookEvent),
	}
	h.cond = sync.NewCond(&h.mu)
	go h.read(in)
	return h
}

// read は、in の 1 行を Enter として 1 つだけ覚える。まだ使っていない Enter があるあいだの行は捨てる。
func (h *Hook) read(in io.Reader) {
	lines := bufio.NewScanner(in)
	for lines.Scan() {
		h.mu.Lock()
		h.pending = true
		h.cond.Broadcast()
		h.mu.Unlock()
	}
}

// Prepare は、受話器を下ろした状態からこの電話の上げ下げを知らせ始める。
// 待っていた Enter は捨てるので、次の電話には出ない。
func (h *Hook) Prepare() {
	h.Rest()
	ctx, cancel := context.WithCancel(context.Background())
	stopped := make(chan struct{})
	h.mu.Lock()
	h.pending = false
	h.up = false
	h.cancel = cancel
	h.stopped = stopped
	h.mu.Unlock()
	go func() {
		defer close(stopped)
		h.watch(ctx)
	}()
}

// Rest は、この電話の上げ下げを知らせるのをやめる。
// 前の監視が終わるまで待つ。終わっていない監視が次の Enter を取ると、その電話に出られない。
func (h *Hook) Rest() {
	h.mu.Lock()
	cancel := h.cancel
	stopped := h.stopped
	h.cancel = nil
	h.stopped = nil
	h.up = false
	if cancel != nil {
		cancel()
	}
	h.cond.Broadcast()
	h.mu.Unlock()
	if stopped != nil {
		<-stopped
	}
	// 前の電話の上げ下げが、次の電話の受け取りに残らないように 1 つ捨てる。
	select {
	case <-h.events:
	default:
	}
}

func (h *Hook) watch(ctx context.Context) {
	for {
		h.mu.Lock()
		for !h.pending && ctx.Err() == nil {
			h.cond.Wait()
		}
		if ctx.Err() != nil {
			h.mu.Unlock()
			return
		}
		h.pending = false
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
