//go:build darwin

package main

import (
	"errors"
	"io"
	"os"

	"github.com/gesop0n/kazokuai/device/mac"
	"github.com/gesop0n/kazokuai/device/phone"
)

func openPhone(out io.Writer) (phone.Phone, func(), error) {
	handset, err := mac.OpenHandset()
	if err != nil {
		return phone.Phone{}, nil, err
	}
	hook := mac.NewHook(os.Stdin, out)
	return phone.Phone{
		Handset: handset,
		Hook:    hook,
		Keypad:  hook,
		Ringer:  mac.Ringer{Out: out},
		Lamp:    mac.Lamp{Out: out},
	}, handset.Close, nil
}

// echoesSpeech は、読み上げた文をターミナルにも書く。
func echoesSpeech() bool { return true }

func runCheck(string) error {
	return errors.New("部品の確認は電話機の上で行ってください")
}
