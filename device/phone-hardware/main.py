#!/usr/bin/env python3
"""Hardware checks and a local telephone demo, without Gemini."""
import argparse
from collections import deque
from contextlib import ExitStack
from time import monotonic, sleep

import config


def make_audio(stack):
    from audio_device import AudioDevice
    from microphone import Microphone
    from speaker import Speaker
    audio = stack.enter_context(AudioDevice(
        config.INPUT_DEVICE, config.OUTPUT_DEVICE, config.AUDIO_RATE, config.MIC_CHANNEL))
    return (audio, Microphone(audio),
            Speaker(audio, config.SPEAKER_GAIN, config.SPEAKER_PEAK_LIMIT))


def main():
    parser = argparse.ArgumentParser(description="電話の部品別テスト。終了はCtrl+C。")
    parser.add_argument("mode", choices=("devices", "speaker", "mic", "ringer", "keypad", "hook", "demo"))
    args = parser.parse_args()
    try:
        with ExitStack() as stack:
            if args.mode == "devices":
                import sounddevice as sd
                print(sd.query_devices())
                return
            if args.mode in ("speaker", "mic", "demo"):
                import numpy as np
                audio, mic, speaker = make_audio(stack)
            if args.mode in ("ringer", "keypad", "hook", "demo"):
                from gpiozero.pins.lgpio import LGPIOFactory
                factory = LGPIOFactory()
                stack.callback(factory.close)
            if args.mode in ("ringer", "demo"):
                from ringer import Ringer
                ringer = Ringer(config.RINGER_GPIO, factory)
                stack.callback(ringer.close)
            if args.mode in ("keypad", "demo"):
                from keypad import Keypad
                keypad = Keypad(config.ROW_GPIO, config.COL_GPIO, config.KEYS, factory)
                stack.callback(keypad.close)
            if args.mode in ("hook", "demo"):
                from hook import HookSwitch
                hook = HookSwitch(config.HOOK_GPIO, config.LIFTED_WHEN_CLOSED,
                                  config.DEBOUNCE_SECONDS, factory)
                stack.callback(hook.close)

            if args.mode == "speaker":
                t = np.arange(audio.rate) / audio.rate
                tone = (0.1 * np.sin(2 * np.pi * 440 * t)).astype(np.float32)
                fade = max(1, audio.rate // 50)
                tone[:fade] *= np.linspace(0, 1, fade)
                tone[-fade:] *= np.linspace(1, 0, fade)
                print("受話器にテスト音を流します。耳から離して確認してください。", flush=True)
                speaker.play(tone)
                while speaker.is_playing:
                    sleep(0.01)
                sleep(0.3)  # allow the hardware output buffer to finish
            elif args.mode == "mic":
                print("5秒間、受話器に話してください。録音後に再生します。", flush=True)
                mic.start()
                blocks = []
                deadline = monotonic() + 5
                while monotonic() < deadline:
                    block = mic.read(timeout=0.1)
                    if block is not None:
                        blocks.append(block)
                dropped = audio.dropped_input_blocks
                mic.stop()
                if blocks:
                    recording = np.concatenate(blocks)
                    print(f"ピーク: {np.max(np.abs(recording)):.4f} / 破棄ブロック: {dropped}", flush=True)
                    speaker.play(recording)
                    while speaker.is_playing:
                        sleep(0.01)
                    sleep(0.3)
                else:
                    print("録音データがありません。入力機器を確認してください。")
            elif args.mode == "ringer":
                print("本体の着信音。Ctrl+Cで停止。", flush=True)
                ringer.start()
                while True:
                    if ringer.error:
                        raise RuntimeError("着信音の生成に失敗しました。") from ringer.error
                    sleep(0.05)
            elif args.mode == "keypad":
                print("キーを1個ずつ押してください。", flush=True)
                while True:
                    key = keypad.read_key()
                    if key is not None:
                        print(f"キー: {key}", flush=True)
                    sleep(0.005)
            elif args.mode == "hook":
                previous = None
                while True:
                    lifted = hook.is_lifted
                    if lifted != previous:
                        print("受話器: 上がっている" if lifted else "受話器: 置かれている", flush=True)
                        previous = lifted
                    sleep(0.01)
            elif args.mode == "demo":
                run_demo(audio, mic, speaker, ringer, keypad, hook)
    except KeyboardInterrupt:
        print("\n停止しました。")
    except Exception as error:
        parser.exit(1, f"エラー: {error}\nREADME.mdの設定と配線を確認してください。\n")


def run_demo(audio, mic, speaker, ringer, keypad, hook):
    """Lift: answer; 5: replay recent recording; replace: stop; #: ring again."""
    import numpy as np
    recent = deque()
    frames = 0
    previous_lifted = None
    replaying = False
    print("置いた状態で着信。上げると録音開始。5で直近5秒を再生。置くと停止。", flush=True)
    print("もう一度着信させるには、置いた状態で # を押してください。", flush=True)
    while True:
        lifted = hook.is_lifted
        if lifted != previous_lifted:
            if lifted:
                ringer.stop()
                mic.start()
                print("受話器が上がりました。話してから5を押してください。", flush=True)
            else:
                mic.stop()
                speaker.stop()
                recent.clear()
                frames = 0
                replaying = False
                print("受話器が置かれました。音声を停止しました。", flush=True)
                if previous_lifted is None:
                    ringer.start()
            previous_lifted = lifted
        if lifted and not replaying:
            while True:
                block = mic.read()
                if block is None:
                    break
                recent.append(block)
                frames += len(block)
                while frames > audio.rate * 5 and recent:
                    frames -= len(recent.popleft())
        if replaying and not speaker.is_playing:
            # Do not record our own playback during the test.
            sleep(0.05)
            mic.start()
            replaying = False
        key = keypad.read_key()
        if key is not None:
            print(f"キー: {key}", flush=True)
            if key == "#" and not lifted:
                ringer.start()
            elif key == "5" and lifted and recent and not replaying:
                mic.stop()
                speaker.play(np.concatenate(recent))
                recent.clear()
                frames = 0
                replaying = True
        if ringer.error:
            raise RuntimeError("着信音の生成に失敗しました。") from ringer.error
        sleep(0.005)


if __name__ == "__main__":
    main()
