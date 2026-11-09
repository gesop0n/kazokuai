//go:build linux

package pi

import (
	"context"
	"io"
	"time"

	"github.com/gesop0n/kazokuai/device/handset"
	"github.com/gesop0n/kazokuai/internal/clock"
)

// RunCheck は、`device check` の部品を電話機の上で動かす。
// getenv は、設定ファイルを読んだあとの環境である。キーパッドもこれを使う。
func RunCheck(ctx context.Context, part string, cfg Config, getenv func(string) string, out io.Writer) error {
	return runCheck(ctx, part, hardware{
		out:    out,
		cfg:    cfg,
		getenv: getenv,
		list: func() (string, error) {
			playback, capture, err := handset.Devices()
			if err != nil {
				return "", err
			}
			return handset.FormatDevices(playback, capture), nil
		},
		open:   func() (ear, error) { return OpenHandset(cfg) },
		line:   func() (Line, error) { return OpenLine(cfg) },
		bell:   func() (bell, error) { return OpenRinger(cfg, out) },
		record: 5 * time.Second,
		tail:   300 * time.Millisecond,
		tone:   time.Second,
	})
}

// OpenHook は、GPIO のフックを電話の上げ下げにつなぐ。
func OpenHook(cfg Config, out io.Writer) (*Hook, error) {
	line, err := OpenLine(cfg)
	if err != nil {
		return nil, err
	}
	return newHook(line, cfg, clock.Real{}, out), nil
}
