"""Stable-time debounce shared by the hook and keypad."""
from time import monotonic


class Debouncer:
    def __init__(self, initial, seconds):
        self.value = initial
        self._candidate = initial
        self._changed = monotonic()
        self._seconds = seconds

    def update(self, value, now=None):
        now = monotonic() if now is None else now
        if value != self._candidate:
            self._candidate = value
            self._changed = now
        if now - self._changed >= self._seconds:
            self.value = self._candidate
        return self.value
