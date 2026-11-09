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
	return phone.Phone{
		Handset: handset,
		Hook:    mac.NewHook(os.Stdin, out),
		Ringer:  mac.Ringer{Out: out},
		Lamp:    mac.Lamp{Out: out},
	}, handset.Close, nil
}

func runCheck(string) error {
	return errors.New("部品の確認は電話機の上で行ってください")
}
