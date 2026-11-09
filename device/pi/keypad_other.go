//go:build !linux

package pi

import "errors"

// OpenKeypad は、キーパッドの GPIO を電話機の上で開く。
func OpenKeypad(string, KeypadConfig) (*Keypad, error) {
	return nil, errors.New("キーパッドは電話機の上で読んでください")
}
