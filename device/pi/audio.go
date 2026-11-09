package pi

import (
	"errors"
	"strings"

	"github.com/gesop0n/kazokuai/device/handset"
)

// OpenHandset は、名前で選んだ USB のアダプターに受話器を開く。
func OpenHandset(cfg Config) (*handset.Handset, error) {
	if strings.TrimSpace(cfg.AudioDevice) == "" {
		return nil, errors.New("音声の機器の名前が要ります。KAZOKUAI_AUDIO_DEVICE に、機器名の一部を入れてください")
	}
	return handset.Open(handset.Options{
		DeviceName: cfg.AudioDevice,
		MicChannel: cfg.MicChannel,
		Gain:       cfg.SpeakerGain,
		Limit:      cfg.SpeakerLimit,
	})
}
