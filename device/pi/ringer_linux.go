//go:build linux

package pi

import (
	"fmt"
	"io"

	"github.com/warthog618/go-gpiocdev"

	"github.com/gesop0n/kazokuai/internal/clock"
)

// OpenRinger は、呼び出し音の GPIO を出力として開く。始まるときは切っておく。
func OpenRinger(cfg Config, out io.Writer) (*Ringer, error) {
	line, err := gpiocdev.RequestLine(cfg.GPIOChip, cfg.RingerGPIO,
		gpiocdev.WithConsumer("kazokuai"),
		gpiocdev.AsOutput(0),
	)
	if err != nil {
		return nil, fmt.Errorf("呼び出し音の %s GPIO%d を開けなかった: %w", cfg.GPIOChip, cfg.RingerGPIO, err)
	}
	return newRinger(gpioPin{line: line}, clock.Real{}, out), nil
}

// gpioPin は、go-gpiocdev の出力である。
type gpioPin struct {
	line *gpiocdev.Line
}

func (p gpioPin) Set(level int) error { return p.line.SetValue(level) }

func (p gpioPin) Close() error { return p.line.Close() }
