"""Scan isolated matrix contacts; unused rows stay high impedance."""
from time import sleep
from debounce import Debouncer


class Keypad:
    def __init__(self, rows, columns, keys, pin_factory, debounce=0.03):
        if len(keys) != len(rows) or any(len(row) != len(columns) for row in keys):
            raise ValueError("キー配置と行・列の数が一致しません。")
        self._rows = []
        self._columns = []
        self._keys = keys
        self._state = Debouncer(frozenset(), debounce)
        self._ready = True
        try:
            for gpio in rows:
                pin = pin_factory.pin(gpio)
                self._rows.append(pin)
                pin.input_with_pull("floating")
            for gpio in columns:
                pin = pin_factory.pin(gpio)
                self._columns.append(pin)
                pin.input_with_pull("up")
        except BaseException:
            self.close()
            raise

    def _scan(self):
        pressed = set()
        for r, row in enumerate(self._rows):
            row.output_with_state(False)
            try:
                sleep(0.001)
                for c, col in enumerate(self._columns):
                    if not col.state:
                        pressed.add((r, c))
            finally:
                row.input_with_pull("floating")
        return frozenset(pressed)

    def read_key(self):
        """Poll regularly. Emit one press; held keys do not repeat."""
        pressed = self._scan()
        if len(pressed) > 1:
            self._ready = False  # suppress ghosting until stable full release
        stable = self._state.update(pressed)
        if not stable and not pressed:
            self._ready = True
        elif len(stable) == 1 and self._ready:
            self._ready = False
            r, c = next(iter(stable))
            return self._keys[r][c]
        return None

    def close(self):
        for pin in self._rows + self._columns:
            pin.input_with_pull("floating")
            pin.close()
