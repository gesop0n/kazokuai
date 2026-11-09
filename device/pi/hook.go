package pi

import (
	"context"
	"fmt"
	"io"
	"sync"
	"time"

	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/internal/clock"
)

// Hook は、受話器の上げ下げを電話に知らせる。
// 電話のたびに置いた状態から始め、すでに上がっている受話器では出ない。
type Hook struct {
	line             Line
	liftedWhenClosed bool
	debounce         time.Duration
	clock            clock.Clock
	out              io.Writer
	events           chan phone.HookEvent

	mu      sync.Mutex
	cancel  context.CancelFunc
	stopped chan struct{}
	started chan struct{}
}

func newHook(line Line, cfg Config, clk clock.Clock, out io.Writer) *Hook {
	if clk == nil {
		clk = clock.Real{}
	}
	if out == nil {
		out = io.Discard
	}
	return &Hook{
		line:             line,
		liftedWhenClosed: cfg.LiftedWhenClosed,
		debounce:         cfg.Debounce,
		clock:            clk,
		out:              out,
		events:           make(chan phone.HookEvent),
	}
}

// Prepare は、受話器を置いた状態から、この電話の上げ下げを知らせ始める。
// 待っているあいだの変化は、次の電話の受話器上げにしない。
func (h *Hook) Prepare() {
	h.Rest()
	ctx, cancel := context.WithCancel(context.Background())
	stopped := make(chan struct{})
	started := make(chan struct{})
	h.mu.Lock()
	h.cancel = cancel
	h.stopped = stopped
	h.started = started
	h.mu.Unlock()
	go func() {
		defer close(stopped)
		h.watch(ctx, started)
	}()
}

// Rest は、この電話の上げ下げを知らせるのをやめる。
func (h *Hook) Rest() {
	h.mu.Lock()
	cancel := h.cancel
	stopped := h.stopped
	h.cancel = nil
	h.stopped = nil
	if cancel != nil {
		cancel()
	}
	h.mu.Unlock()
	if stopped != nil {
		<-stopped
	}
	select {
	case <-h.events:
	default:
	}
}

func (h *Hook) Events() <-chan phone.HookEvent { return h.events }

// Close は、この電話の監視をやめ、接点を放す。
func (h *Hook) Close() error {
	h.Rest()
	if h.line == nil {
		return nil
	}
	return h.line.Close()
}

func (h *Hook) watch(ctx context.Context, started chan struct{}) {
	var once sync.Once
	ready := func() { once.Do(func() { close(started) }) }
	defer ready()

	h.drain()
	raw, err := h.line.Value()
	if err != nil {
		fmt.Fprintf(h.out, "フックを読めなかった: %v\n", err)
		return
	}
	state := newContact(raw, h.clock.Now(), h.liftedWhenClosed, h.debounce)
	ready()
	for {
		if ev, ok := state.level(raw, h.clock.Now()); ok {
			if !h.send(ctx, ev) {
				return
			}
		}
		wait := h.debounce
		if wait <= 0 {
			// デバウンスが 0 のときは、変化が来たその場で安定する。空回りしない。
			wait = time.Hour
		}
		timer := h.clock.NewTimer(wait)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case next, ok := <-h.line.Changes():
			timer.Stop()
			if !ok {
				return
			}
			raw = next
		case <-timer.Chan():
		}
	}
}

func (h *Hook) drain() {
	for {
		select {
		case <-h.line.Changes():
		default:
			return
		}
	}
}

func (h *Hook) send(ctx context.Context, ev phone.HookEvent) bool {
	line := "受話器を置きました。"
	if ev == phone.PickedUp {
		line = "受話器を上げました。"
	}
	fmt.Fprintln(h.out, line)
	select {
	case <-ctx.Done():
		return false
	case h.events <- ev:
		return true
	}
}

// Watch は、フックの今の状態と、そのあとの変化を出す。確認コマンドが使う。
// 上がったままでも、その状態をそのまま書く。
func Watch(ctx context.Context, line Line, liftedWhenClosed bool, debounce time.Duration, clk clock.Clock, out io.Writer) error {
	if clk == nil {
		clk = clock.Real{}
	}
	raw, err := line.Value()
	if err != nil {
		return fmt.Errorf("フックを読めなかった: %w", err)
	}
	points := newDebouncer(raw, clk.Now(), debounce)
	prev := contactLifted(points.value, liftedWhenClosed)
	fmt.Fprintln(out, hookState(prev))
	for {
		wait := debounce
		if wait <= 0 {
			wait = time.Hour
		}
		timer := clk.NewTimer(wait)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case next, ok := <-line.Changes():
			timer.Stop()
			if !ok {
				return nil
			}
			raw = next
		case <-timer.Chan():
		}
		up := contactLifted(points.update(raw, clk.Now()), liftedWhenClosed)
		if up != prev {
			prev = up
			fmt.Fprintln(out, hookState(up))
		}
	}
}

func contactLifted(raw int, liftedWhenClosed bool) bool {
	closed := raw == 0
	if liftedWhenClosed {
		return closed
	}
	return !closed
}

func hookState(up bool) string {
	if up {
		return "受話器: 上がっている"
	}
	return "受話器: 置かれている"
}
