//go:build linux

package pi

import (
	"fmt"

	"github.com/warthog618/go-gpiocdev"
)

// OpenLine は、フックの接点を GPIO で開く。内部プルアップと、カーネルのデバウンスを付ける。
// 0 が GND へ閉じた状態、1 が開いた状態である。
// カーネルが揺れを落としたあとも、Hook は同じ時間だけ値が続いてから電話に出す。
func OpenLine(cfg Config) (Line, error) {
	changes := make(chan int, 16)
	line, err := gpiocdev.RequestLine(cfg.GPIOChip, cfg.HookGPIO,
		gpiocdev.WithConsumer("kazokuai"),
		gpiocdev.WithPullUp,
		gpiocdev.WithDebounce(cfg.Debounce),
		gpiocdev.WithBothEdges,
		gpiocdev.WithEventHandler(func(evt gpiocdev.LineEvent) {
			level := 0
			if evt.Type == gpiocdev.LineEventRisingEdge {
				level = 1
			}
			select {
			case changes <- level:
			default:
			}
		}),
	)
	if err != nil {
		return nil, fmt.Errorf("フックの %s GPIO%d を開けなかった: %w", cfg.GPIOChip, cfg.HookGPIO, err)
	}
	return &gpioLine{line: line, changes: changes}, nil
}

// gpioLine は、go-gpiocdev の 1 本の線である。
type gpioLine struct {
	line    *gpiocdev.Line
	changes chan int
}

func (g *gpioLine) Value() (int, error) {
	return g.line.Value()
}

func (g *gpioLine) Changes() <-chan int { return g.changes }

func (g *gpioLine) Close() error { return g.line.Close() }
