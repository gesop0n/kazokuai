"""Nonblocking handset playback, duplicated to both output channels."""
import numpy as np


class Speaker:
    def __init__(self, audio_device, gain=0.5, peak_limit=0.1):
        if not 0 < gain <= 4 or not 0 < peak_limit <= 1:
            raise ValueError("gainは0より大きく4以下、peak_limitは0より大きく1以下です。")
        self._audio = audio_device
        self.gain = gain
        self.peak_limit = peak_limit

    def play(self, audio, sample_rate=None):
        """Queue mono float samples in [-1,1]. Returns without waiting."""
        self._audio._require_open()
        mono = np.asarray(audio, dtype=np.float32)
        if mono.ndim != 1 or not np.all(np.isfinite(mono)):
            raise ValueError("音声は有限値の1次元float配列で渡してください。")
        source_rate = self._audio.rate if sample_rate is None else sample_rate
        if source_rate <= 0:
            raise ValueError("sample_rateは正の値です。")
        if not len(mono):
            return
        if len(mono) / source_rate > 10:
            raise BufferError("音声は10秒以下の長さに分けてください。")
        if source_rate != self._audio.rate:
            count = max(1, round(len(mono) * self._audio.rate / source_rate))
            mono = np.interp(np.arange(count) / self._audio.rate,
                             np.arange(len(mono)) / source_rate, mono).astype(np.float32)
        mono = mono * self.gain
        peak = float(np.max(np.abs(mono)))
        if peak > self.peak_limit:
            mono *= self.peak_limit / peak
        self._audio.enqueue(mono)

    @property
    def is_playing(self):
        return self._audio.is_playing

    def stop(self):
        """Discard queued audio. Hardware latency may leave a short tail."""
        self._audio.stop_playback()

    close = stop
