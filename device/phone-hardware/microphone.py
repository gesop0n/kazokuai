"""Receive mono float32 samples. No network or Gemini dependency."""


class Microphone:
    def __init__(self, audio_device):
        self._audio = audio_device

    @property
    def sample_rate(self):
        return self._audio.rate

    def start(self):
        self._audio.start_capture()

    def read(self, timeout=0):
        """Return one mono block, or None. Default: do not wait."""
        return self._audio.read(timeout)

    def stop(self):
        self._audio.stop_capture()

    close = stop
