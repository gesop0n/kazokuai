// Package clock は、本番の時計とテストの偽の時計が同じ形で時間を進めるための型である。
package clock

import "time"

// Clock は、今の時刻と、一度だけ鳴るタイマーを返す。
type Clock interface {
	// Now は、今の時刻を返す。
	Now() time.Time
	// NewTimer は、d が経ったことを知らせるタイマーを返す。d が 0 以下なら、すぐ知らせる。
	NewTimer(d time.Duration) Timer
}

// Timer は、時間が経ったことを Chan で 1 回知らせる。
type Timer interface {
	Chan() <-chan time.Time
	// Stop は、まだ知らせていなければ、知らせないようにする。
	Stop()
}

// Real は、そのマシンの時計である。
type Real struct{}

func (Real) Now() time.Time { return time.Now() }

func (Real) NewTimer(d time.Duration) Timer {
	return realTimer{time.NewTimer(d)}
}

type realTimer struct{ timer *time.Timer }

func (t realTimer) Chan() <-chan time.Time { return t.timer.C }

func (t realTimer) Stop() { t.timer.Stop() }
