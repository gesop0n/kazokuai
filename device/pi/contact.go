package pi

import (
	"time"

	"github.com/gesop0n/kazokuai/device/phone"
)

// debouncer は、同じ値が debounce のあいだ続いてから、その値を安定とみなす。
type debouncer struct {
	value     int
	candidate int
	changed   time.Time
	debounce  time.Duration
}

func newDebouncer(initial int, now time.Time, debounce time.Duration) *debouncer {
	return &debouncer{value: initial, candidate: initial, changed: now, debounce: debounce}
}

func (d *debouncer) update(raw int, now time.Time) int {
	if raw != d.candidate {
		d.candidate = raw
		d.changed = now
	}
	if now.Sub(d.changed) >= d.debounce {
		d.value = d.candidate
	}
	return d.value
}

// contact は、接点のレベルから、電話に出るか切るかを決める。
// 電話の開始時にすでに上がっている受話器は、一度置いてから上げるまで出ない。
type contact struct {
	liftedWhenClosed bool
	points           *debouncer
	seenDown         bool
	up               bool
}

func newContact(initial int, now time.Time, liftedWhenClosed bool, debounce time.Duration) *contact {
	c := &contact{
		liftedWhenClosed: liftedWhenClosed,
		points:           newDebouncer(initial, now, debounce),
	}
	c.seenDown = !c.lifted(initial)
	return c
}

// level は、プルアップされた接点のレベルを渡す。0 が閉じ、1 が開いている。
func (c *contact) level(raw int, now time.Time) (phone.HookEvent, bool) {
	if !c.lifted(c.points.update(raw, now)) {
		c.seenDown = true
		if c.up {
			c.up = false
			return phone.PutDown, true
		}
		return 0, false
	}
	if !c.seenDown || c.up {
		return 0, false
	}
	c.up = true
	return phone.PickedUp, true
}

func (c *contact) lifted(raw int) bool {
	return contactLifted(raw, c.liftedWhenClosed)
}
