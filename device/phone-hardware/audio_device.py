"""Shared duplex USB stream. Microphone/Speaker expose the public operations."""
from collections import deque
from queue import Empty, Full, Queue
from threading import Lock

import numpy as np
import sounddevice as sd


class AudioDevice:
    def __init__(self, input_device=1, output_device=1, rate=None, mic_channel=0):
        self.input_device = input_device
        self.output_device = output_device
        self.mic_channel = mic_channel
        self.rate = rate
        self.input_channels = 0
        self.output_channels = 0
        self._stream = None
        self._recording = False
        self._input = Queue(maxsize=100)  # 2 seconds at 20ms per block
        self._output = deque()
        self._offset = 0
        self._pending_frames = 0
        self._lock = Lock()
        self.dropped_input_blocks = 0
        self.status = ""

    def open(self):
        if self._stream is not None:
            return self
        inp = sd.query_devices(self.input_device, "input")
        out = sd.query_devices(self.output_device, "output")
        self.input_channels = min(2, int(inp["max_input_channels"]))
        self.output_channels = min(2, int(out["max_output_channels"]))
        if not 0 <= self.mic_channel < self.input_channels or self.output_channels < 1:
            raise ValueError("USBの入力・出力番号とMIC_CHANNELを確認してください。")
        self.rate = int(self.rate or out["default_samplerate"])
        sd.check_input_settings(device=self.input_device, channels=self.input_channels,
                                dtype="float32", samplerate=self.rate)
        sd.check_output_settings(device=self.output_device, channels=self.output_channels,
                                 dtype="float32", samplerate=self.rate)
        stream = sd.Stream(device=(self.input_device, self.output_device),
                           samplerate=self.rate, blocksize=max(1, self.rate // 50),
                           channels=(self.input_channels, self.output_channels),
                           dtype="float32", callback=self._callback)
        try:
            stream.start()
        except BaseException:
            stream.close()
            raise
        self._stream = stream
        return self

    def _callback(self, indata, outdata, frames, time_info, status):
        if status:
            self.status = str(status)
        with self._lock:
            if self._recording:
                block = indata[:, self.mic_channel].copy()
                try:
                    self._input.put_nowait(block)
                except Full:
                    self.dropped_input_blocks += 1
            outdata.fill(0)
            written = 0
            while self._output and written < frames:
                block = self._output[0]
                count = min(frames - written, len(block) - self._offset)
                outdata[written:written + count] = block[self._offset:self._offset + count, None]
                written += count
                self._offset += count
                self._pending_frames -= count
                if self._offset == len(block):
                    self._output.popleft()
                    self._offset = 0

    def start_capture(self):
        self._require_open()
        with self._lock:
            self._clear_input()
            self.dropped_input_blocks = 0
            self._recording = True

    def stop_capture(self):
        with self._lock:
            self._recording = False
            self._clear_input()

    def _clear_input(self):
        while True:
            try:
                self._input.get_nowait()
            except Empty:
                return

    def read(self, timeout=0):
        self._require_open()
        try:
            return self._input.get(timeout=timeout)
        except Empty:
            return None

    def enqueue(self, mono):
        self._require_open()
        block = np.array(mono, dtype=np.float32, copy=True)
        with self._lock:
            if self._pending_frames + len(block) > self.rate * 10:
                raise BufferError("再生待ちが10秒を超えました。短い音声に分けて送ってください。")
            if len(block):
                self._output.append(block)
                self._pending_frames += len(block)

    @property
    def is_playing(self):
        with self._lock:
            return self._pending_frames > 0

    def stop_playback(self):
        with self._lock:
            self._output.clear()
            self._offset = 0
            self._pending_frames = 0

    def _require_open(self):
        if self._stream is None:
            raise RuntimeError("先に AudioDevice.open() を呼んでください。")

    def close(self):
        self.stop_capture()
        self.stop_playback()
        if self._stream is not None:
            stream, self._stream = self._stream, None
            try:
                stream.abort()
            finally:
                stream.close()

    __enter__ = open

    def __exit__(self, *args):
        self.close()
