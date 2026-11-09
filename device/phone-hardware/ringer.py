"""PAM8012 body ringer. start() returns immediately; stop() silences it."""
from threading import Event, Thread
from gpiozero import PWMOutputDevice


class Ringer:
    def __init__(self, gpio=18, pin_factory=None):
        self._output = PWMOutputDevice(gpio, frequency=1200, initial_value=0,
                                       pin_factory=pin_factory)
        self._stop = Event()
        self._thread = None
        self.error = None
        self._closed = False

    def start(self):
        if self._closed:
            raise RuntimeError("Ringerはすでにcloseされています。")
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop.clear()
        self.error = None
        self._thread = Thread(target=self._run, daemon=True, name="phone-ringer")
        self._thread.start()

    def _run(self):
        try:
            while not self._stop.is_set():
                for _ in range(16):
                    for frequency in (1200, 1600):
                        if self._stop.is_set():
                            return
                        self._output.frequency = frequency
                        self._output.value = 0.1
                        if self._stop.wait(1 / 32):
                            return
                self._output.off()
                self._stop.wait(2)
        except Exception as error:
            self.error = error
        finally:
            self._output.off()

    def stop(self):
        if self._closed:
            return
        self._stop.set()
        if self._thread is not None:
            self._thread.join()
            self._thread = None
        self._output.off()

    def close(self):
        if self._closed:
            return
        try:
            self.stop()
        finally:
            self._output.close()
            self._closed = True
