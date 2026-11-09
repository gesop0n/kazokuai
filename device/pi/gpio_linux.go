//go:build linux

package pi

import "github.com/warthog618/go-gpiocdev"

// gpioPin は、go-gpiocdev の 1 本の線である。
// 呼び出し音は値で持つ。メソッドは値のレシーバにし、その値をキーパッドの線にもする。
type gpioPin struct {
	line *gpiocdev.Line
}

func (p gpioPin) Set(level int) error { return p.line.SetValue(level) }

func (p gpioPin) DriveLow() error {
	// 0 は非アクティブで、アクティブが高い既定では電気的に低い。
	return p.line.Reconfigure(gpiocdev.AsOutput(0))
}

func (p gpioPin) Float() error {
	return p.line.Reconfigure(gpiocdev.AsInput, gpiocdev.WithBiasDisabled)
}

func (p gpioPin) Value() (int, error) { return p.line.Value() }

// Close は線を放す。呼び出し音の Pin は値で受けるので、ここも値のレシーバである。
// キーパッドが低くした行は、放す前に Keypad.Close がハイインピーダンスへ戻す。
func (p gpioPin) Close() error { return p.line.Close() }

var (
	_ Pin = gpioPin{}
	_ pin = gpioPin{}
)
