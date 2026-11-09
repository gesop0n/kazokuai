// Package clocktest は、テストが待たずに時刻を進めるための時計である。
package clocktest

import (
	"sync"
	"time"

	"github.com/gesop0n/kazokuai/internal/clock"
)

// Clock は、Advance で時刻を進める時計である。
type Clock struct {
	mu      sync.Mutex
	now     time.Time
	waiters []*timer
	added   sync.Cond
}

// New は、now を今の時刻にする時計を返す。
func New(now time.Time) *Clock {
	c := &Clock{now: now}
	c.added.L = &c.mu
	return c
}

func (c *Clock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *Clock) NewTimer(d time.Duration) clock.Timer {
	c.mu.Lock()
	defer c.mu.Unlock()
	t := &timer{
		clock:    c,
		deadline: c.now.Add(d),
		ch:       make(chan time.Time, 1),
	}
	if d <= 0 {
		t.ch <- c.now
		return t
	}
	c.waiters = append(c.waiters, t)
	c.added.Broadcast()
	return t
}

// WaitForTimers は、少なくとも n 個のタイマーが期限を待っている状態になるまで待つ。
// 時刻を進める前に使う。タイマーを作る前に Advance すると、その期限は進めたあとの時刻になり、鳴らない。
func (c *Clock) WaitForTimers(n int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for c.pending() < n {
		c.added.Wait()
	}
}

func (c *Clock) pending() int {
	n := 0
	for _, t := range c.waiters {
		if !t.stopped {
			n++
		}
	}
	return n
}

// Advance は、時計を d 進め、その時刻までに期限が来たタイマーへ知らせる。
func (c *Clock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
	pending := make([]*timer, 0, len(c.waiters))
	for _, t := range c.waiters {
		if t.stopped {
			continue
		}
		if !t.deadline.After(c.now) {
			t.ch <- c.now
			continue
		}
		pending = append(pending, t)
	}
	c.waiters = pending
}

type timer struct {
	clock    *Clock
	deadline time.Time
	ch       chan time.Time
	stopped  bool
}

func (t *timer) Chan() <-chan time.Time { return t.ch }

func (t *timer) Stop() {
	t.clock.mu.Lock()
	defer t.clock.mu.Unlock()
	t.stopped = true
}
