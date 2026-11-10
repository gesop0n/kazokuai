package mac

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"sync"

	"github.com/gesop0n/kazokuai/device/phone"
)

// Hook は、ターミナルのフックとキーパッドである。
// 空の行で受話器を上げ下げし、`#` だけの行が「＃」、`*` だけの行が「＊」である。
// 受話器が上がっているかは監視をまたいで残り、切れ目の空の行は捨てる。
type Hook struct {
	out    io.Writer
	events chan phone.HookEvent
	keys   chan string

	mu      sync.Mutex
	cond    *sync.Cond
	cancel  context.CancelFunc
	stopped chan struct{} // 今の監視が終わると閉じる
	up      bool
	pending bool // まだ上げ下げに使っていない Enter が 1 つある
}

// NewHook は、in の空の行をフック、それ以外の行をキーとして受ける。
// `#` だけの行が「＃」、`*` だけの行が「＊」である。上げたときと置いたときを out に書く。
// 上げ下げを知らせるのは、Prepare から Rest までのあいだだけである。
func NewHook(in io.Reader, out io.Writer) *Hook {
	h := &Hook{
		out:    out,
		events: make(chan phone.HookEvent),
		keys:   make(chan string, 1),
	}
	h.cond = sync.NewCond(&h.mu)
	go h.read(in)
	return h
}

// read は、空の行を Enter として 1 つだけ覚え、それ以外の行をキーとして渡す。
// まだ使っていない Enter があるあいだの空の行は、その 1 つにまとめる。
func (h *Hook) read(in io.Reader) {
	lines := bufio.NewScanner(in)
	for lines.Scan() {
		text := lines.Text()
		if text != "" {
			h.keys <- text
			continue
		}
		h.mu.Lock()
		h.pending = true
		h.cond.Broadcast()
		h.mu.Unlock()
	}
}

// Prepare は、このあいだの上げ下げを知らせ始める。
// 受話器が上がっているかは残す。待っていた Enter は捨てるので、次の電話には出ない。
func (h *Hook) Prepare() {
	h.Rest()
	ctx, cancel := context.WithCancel(context.Background())
	stopped := make(chan struct{})
	h.mu.Lock()
	h.pending = false
	h.cancel = cancel
	h.stopped = stopped
	h.mu.Unlock()
	go func() {
		defer close(stopped)
		h.watch(ctx)
	}()
}

// Rest は、このあいだの上げ下げを知らせるのをやめる。受話器が上がっているかは残す。
// 前の監視が終わるまで待つ。終わっていない監視が次の Enter を取ると、その電話に出られない。
func (h *Hook) Rest() {
	h.mu.Lock()
	cancel := h.cancel
	stopped := h.stopped
	h.cancel = nil
	h.stopped = nil
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

// Lifted は、受話器が上がっているかである。監視をまたいで残る。
func (h *Hook) Lifted() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.up
}

// Keys は、空でない行を 1 つずつ返す。`#` だけの行が「＃」、`*` だけの行が「＊」である。
func (h *Hook) Keys() <-chan string { return h.keys }

var _ phone.Keypad = (*Hook)(nil)

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
