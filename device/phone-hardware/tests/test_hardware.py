"""Hardware substitutes: these checks never open GPIO or audio devices."""
import sys
import types
import unittest
from unittest.mock import patch
from time import sleep

import numpy as np


class FakeStream:
    def __init__(self, **settings):
        self.settings = settings
        self.closed = False
    def start(self):
        pass
    def abort(self):
        pass
    def close(self):
        self.closed = True


sound = types.ModuleType("sounddevice")
sound.query_devices = lambda *args: {
    "max_input_channels": 2, "max_output_channels": 2, "default_samplerate": 48000}
sound.check_input_settings = lambda **kwargs: None
sound.check_output_settings = lambda **kwargs: None
sound.Stream = FakeStream


class FakePWM:
    def __init__(self, *args, **kwargs):
        self.value = 0
        self.frequency = 1200
        self.closed = False
    def off(self):
        if self.closed:
            raise RuntimeError("device closed")
        self.value = 0
    def close(self):
        self.closed = True


class FakeButton:
    def __init__(self, *args, **kwargs):
        self.is_pressed = False
    def close(self):
        pass


gpio = types.ModuleType("gpiozero")
gpio.PWMOutputDevice = FakePWM
gpio.Button = FakeButton
# Temporary imports prevent these substitutes from affecting real hardware runs.
with patch.dict(sys.modules, {"sounddevice": sound, "gpiozero": gpio}):
    from audio_device import AudioDevice
    from microphone import Microphone
    from speaker import Speaker
    from ringer import Ringer
    from hook import HookSwitch
from keypad import Keypad
from debounce import Debouncer


class AudioTests(unittest.TestCase):
    def setUp(self):
        self.audio = AudioDevice(mic_channel=1).open()
    def tearDown(self):
        self.audio.close()
    def tick(self, frames=960):
        inp = np.zeros((frames, 2), np.float32)
        inp[:, 1] = 0.2
        out = np.empty_like(inp)
        self.audio._callback(inp, out, frames, None, "")
        return out
    def test_duplex_capture_and_resampled_playback(self):
        mic = Microphone(self.audio)
        speaker = Speaker(self.audio)
        mic.start()
        speaker.play(np.ones(320, np.float32), sample_rate=16000)
        out = self.tick()
        self.assertTrue(np.allclose(mic.read(), 0.2))
        self.assertTrue(np.allclose(out, 0.1))
        self.assertFalse(speaker.is_playing)
        self.assertEqual(self.audio._stream.settings["device"], (1, 1))
    def test_stop_discards_pending_audio_and_recording(self):
        mic = Microphone(self.audio)
        speaker = Speaker(self.audio)
        mic.start()
        speaker.play(np.ones(48000, np.float32))
        self.tick()
        mic.stop()
        speaker.stop()
        self.assertIsNone(mic.read())
        self.assertTrue(np.all(self.tick() == 0))
        self.assertFalse(speaker.is_playing)
    def test_capture_overflow_is_visible_and_bounded(self):
        self.audio.start_capture()
        for _ in range(105):
            self.tick()
        self.assertEqual(self.audio.dropped_input_blocks, 5)
        self.assertEqual(self.audio._input.qsize(), 100)
    def test_playback_buffer_limit_and_bad_samples(self):
        speaker = Speaker(self.audio)
        speaker.play(np.zeros(480000, np.float32))
        with self.assertRaises(BufferError):
            speaker.play(np.ones(1, np.float32))
        with self.assertRaises(ValueError):
            speaker.play(np.array([np.nan]))
    def test_start_failure_closes_stream(self):
        class Broken(FakeStream):
            def start(self):
                raise RuntimeError("cannot start")
        stream = Broken()
        with patch.object(sound, "Stream", return_value=stream):
            with self.assertRaises(RuntimeError):
                AudioDevice().open()
        self.assertTrue(stream.closed)


class InputTests(unittest.TestCase):
    def test_stable_time_rejects_bounce(self):
        d = Debouncer(False, 0.05)
        self.assertFalse(d.update(True, 1))
        self.assertFalse(d.update(False, 1.02))
        self.assertFalse(d.update(True, 1.03))
        self.assertTrue(d.update(True, 1.09))
    def test_hook_both_polarities(self):
        for polarity in (False, True):
            hook = HookSwitch(lifted_when_closed=polarity, debounce=0)
            hook._button.is_pressed = True
            self.assertEqual(hook.is_lifted, polarity)
            hook._button.is_pressed = False
            self.assertEqual(hook.is_lifted, not polarity)
            hook.close()
    def test_key_hold_and_multiple_press_lockout(self):
        k = Keypad.__new__(Keypad)
        k._keys = (("1", "2"), ("4", "5"))
        k._state = Debouncer(frozenset(), 0)
        k._ready = True
        press = frozenset({(1, 1)})
        k._scan = lambda: press
        self.assertEqual(k.read_key(), "5")
        self.assertIsNone(k.read_key())
        press = frozenset({(0, 0), (1, 1)})
        self.assertIsNone(k.read_key())
        press = frozenset({(0, 0)})
        self.assertIsNone(k.read_key())
        press = frozenset()
        self.assertIsNone(k.read_key())
        press = frozenset({(0, 0)})
        self.assertEqual(k.read_key(), "1")
    def test_scan_restores_row_after_exception(self):
        class Pin:
            floating = False
            def output_with_state(self, value):
                self.floating = False
            def input_with_pull(self, value):
                self.floating = True
            @property
            def state(self):
                raise RuntimeError("read failed")
        row = Pin()
        keypad = Keypad.__new__(Keypad)
        keypad._rows = [row]
        keypad._columns = [Pin()]
        with self.assertRaises(RuntimeError):
            keypad._scan()
        self.assertTrue(row.floating)


class RingerTests(unittest.TestCase):
    def test_stop_is_prompt_idempotent_and_can_restart(self):
        ringer = Ringer()
        ringer.start()
        thread = ringer._thread
        ringer.start()
        self.assertIs(ringer._thread, thread)
        sleep(0.01)
        ringer.stop()
        self.assertFalse(thread.is_alive())
        self.assertEqual(ringer._output.value, 0)
        ringer.start()
        ringer.close()
        ringer.close()
        self.assertTrue(ringer._output.closed)


if __name__ == "__main__":
    unittest.main()
