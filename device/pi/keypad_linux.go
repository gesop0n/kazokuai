//go:build linux

package pi

import (
	"errors"
	"fmt"
	"strings"

	"github.com/warthog618/go-gpiocdev"
)

// OpenKeypad は、行列の GPIO を開く。行はハイインピーダンス、列はプルアップの入力で始める。
// 0 が低い。列が 0 のとき、その行のキーが押されている。
func OpenKeypad(chip string, cfg KeypadConfig) (*Keypad, error) {
	if err := validateKeypad(cfg); err != nil {
		return nil, err
	}
	if strings.TrimSpace(chip) == "" {
		return nil, errors.New("キーパッドの GPIO チップが要ります")
	}
	var opened []pin
	closeOpened := func() {
		for _, p := range opened {
			p.Close()
		}
	}
	rows := make([]pin, 0, len(cfg.Rows))
	for _, gpio := range cfg.Rows {
		p, err := openKeypadPin(chip, gpio, false)
		if err != nil {
			closeOpened()
			return nil, err
		}
		opened = append(opened, p)
		rows = append(rows, p)
	}
	cols := make([]pin, 0, len(cfg.Cols))
	for _, gpio := range cfg.Cols {
		p, err := openKeypadPin(chip, gpio, true)
		if err != nil {
			closeOpened()
			return nil, err
		}
		opened = append(opened, p)
		cols = append(cols, p)
	}
	pad, err := newKeypad(rows, cols, cfg.Keys, cfg.Debounce, nil)
	if err != nil {
		closeOpened()
		return nil, err
	}
	return pad, nil
}

func openKeypadPin(chip string, gpio int, pullUp bool) (pin, error) {
	bias := gpiocdev.LineReqOption(gpiocdev.WithBiasDisabled)
	if pullUp {
		bias = gpiocdev.WithPullUp
	}
	line, err := gpiocdev.RequestLine(chip, gpio,
		gpiocdev.WithConsumer("kazokuai"),
		gpiocdev.AsInput,
		bias,
	)
	if err != nil {
		return nil, fmt.Errorf("キーパッドの %s GPIO%d を開けなかった: %w", chip, gpio, err)
	}
	return &gpioPin{line: line}, nil
}

// gpioPin は、走査のために入力と出力を切り替える 1 本の線である。
type gpioPin struct {
	line *gpiocdev.Line
}

func (p *gpioPin) DriveLow() error {
	// 0 は非アクティブで、アクティブが高い既定では電気的に低い。
	return p.line.Reconfigure(gpiocdev.AsOutput(0))
}

func (p *gpioPin) Float() error {
	return p.line.Reconfigure(gpiocdev.AsInput, gpiocdev.WithBiasDisabled)
}

func (p *gpioPin) Value() (int, error) { return p.line.Value() }

func (p *gpioPin) Close() error {
	floatErr := p.Float()
	err := p.line.Close()
	if err != nil {
		return err
	}
	return floatErr
}
