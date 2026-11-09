"""An isolated handset switch between GPIO and GND, with pull-up."""
from gpiozero import Button
from debounce import Debouncer


class HookSwitch:
    def __init__(self, gpio=5, lifted_when_closed=True, debounce=0.05, pin_factory=None):
        self._button = Button(gpio, pull_up=True, pin_factory=pin_factory)
        self._lifted_when_closed = lifted_when_closed
        self._state = Debouncer(self._raw(), debounce)

    def _raw(self):
        return self._button.is_pressed == self._lifted_when_closed

    @property
    def is_lifted(self):
        """Poll regularly (e.g. every 10ms) to update debounced state."""
        return self._state.update(self._raw())

    def close(self):
        self._button.close()
