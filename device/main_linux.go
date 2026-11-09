//go:build linux

package main

import (
	"context"
	"io"
	"os"
	"os/signal"

	"github.com/gesop0n/kazokuai/device/phone"
	"github.com/gesop0n/kazokuai/device/pi"
)

func openPhone(out io.Writer) (phone.Phone, func(), error) {
	cfg, err := pi.Load(os.Getenv)
	if err != nil {
		return phone.Phone{}, nil, err
	}
	handset, err := pi.OpenHandset(cfg)
	if err != nil {
		return phone.Phone{}, nil, err
	}
	hook, err := pi.OpenHook(cfg, out)
	if err != nil {
		handset.Close()
		return phone.Phone{}, nil, err
	}
	ringer, err := pi.OpenRinger(cfg, out)
	if err != nil {
		hook.Close()
		handset.Close()
		return phone.Phone{}, nil, err
	}
	return phone.Phone{
		Handset: handset,
		Hook:    hook,
		Ringer:  ringer,
		Lamp:    pi.Lamp{Out: out},
	}, func() {
		ringer.Close()
		hook.Close()
		handset.Close()
	}, nil
}

func runCheck(part string) error {
	cfg, err := pi.Load(os.Getenv)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	return pi.RunCheck(ctx, part, cfg, os.Stdout)
}
