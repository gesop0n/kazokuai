# Raspberry Pi 4 電話部品ライブラリ

マイク、受話器スピーカー、本体着信音、キーパッド、受話器スイッチを
別々のクラスに分けました。Geminiへの接続はまだ含みません。
音声入出力は同じUSBアダプターを使用し、初期設定は入力・出力とも機器番号1です。
以前のテストファイルはそのまま残し、このフォルダーで新しい構成を試せます。

## 導入

WindowsでZIPを D:\Downloads に保存し、PowerShellで転送します。

~~~powershell
scp "D:\Downloads\phone-hardware.zip" tana@kazokuai.local:~/
~~~

ラズパイにSSH接続し、実行します。

~~~bash
sudo apt update
sudo apt install -y unzip python3-venv python3-gpiozero python3-lgpio libportaudio2
unzip phone-hardware.zip
cd ~/phone-hardware
python3 -m venv --system-site-packages .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python main.py devices
~~~

GPIO用のlgpioはaptのものを使うため、この環境は --system-site-packages 付きで作ります。
以前のテストプログラムは停止してから実行してください。同じGPIOを同時に使えません。

## 単体で確認

同じフォルダーで以下を実行します。継続するテストはCtrl+Cで終了します。

| コマンド | 動作 |
|---|---|
| .venv/bin/python main.py devices | USB入力・出力番号の一覧 |
| .venv/bin/python main.py speaker | 受話器で1秒の音を再生 |
| .venv/bin/python main.py mic | 5秒録音して受話器から再生 |
| .venv/bin/python main.py ringer | 本体でプルルルを繰り返す |
| .venv/bin/python main.py keypad | 押された文字を表示 |
| .venv/bin/python main.py hook | 受話器が上がった／置かれた状態を表示 |
| .venv/bin/python main.py demo | 全部を組み合わせたローカル動作確認 |

demoは置いた状態で開始すると着信音を鳴らします。
受話器を上げると着信音が止まり録音が始まります。
話してから「5」を押すと直近約5秒を再生します。
受話器を置くと録音と再生を停止します。置いた状態で「#」を押すと再着信します。
起動時にすでに受話器が上がっていれば、着信音を鳴らさず録音を始めます。
このデモでは再生中の録音を止めます。クラス自体は同時録音・再生に対応しています。

## 設定と配線

変更は config.py にまとめています。USB機器番号は再起動や接続順で変わり得ます。
INPUT_DEVICE / OUTPUT_DEVICE は機器名の文字列でも指定できます。
AUDIO_RATE=None は出力機器の標準レートを選びます。同じレートで入力も開ける必要があります。
開けない場合はデバイスの対応レートを確認し、例えば48000を指定して試してください。
MIC_CHANNEL=0 は入力の第1チャンネルです。第2チャンネルにだけ信号があるなら1にします。
SPEAKER_GAIN=0.5、SPEAKER_PEAK_LIMIT=0.1 から始め、耳から離して確認します。
ソフトの信号振幅制限は耳元の音圧を保証しません。

| 用途 | BCM番号 | 物理ピン |
|---|---|---|
| キー R1 / R2 / R3 / R4 | 17 / 27 / 22 / 23 | 11 / 13 / 15 / 16 |
| キー C1 / C2 / C3 | 24 / 25 / 4 | 18 / 22 / 7 |
| 本体着信音 | 18 | 12 |
| 受話器スイッチ | 5 | 29 |
| スイッチのもう片側 | GND | 30 |

キーパッドは従来の3列4行設定です。5以外のキー配置は実機で確認し、KEYSを修正してください。
複数キーが押された場合は、全キーを離すまで入力を受け付けません。
C4やVSSなど、上表にない電話基板の端子は接続しません。
受話器のスピーカーとマイクは動作確認済みのUSB配線をそのまま使います。

受話器スイッチは元の電話回路から電気的に切り離した無電圧接点を使用します。
切替接点の場合は、使わない側も含めて接点グループ全体を切り離します。
GPIOに電話回線や元基板の電圧を加えないでください。
上げると接点が閉じる場合は LIFTED_WHEN_CLOSED=True、
開く場合はFalseにします。まず hook テストで確認してください。

本体着信音は既存のPAM8012配線（入力コンデンサー内蔵モジュール想定）を引き継ぎます。
GPIO18 → 10kΩ → 分岐点 → IN+、分岐点 → 1kΩ → GND。
V+は5V、GNDとIN−はPiのGND。SPK+/SPK−は本体の8Ωスピーカーだけにつなぎます。
SPK−をGNDやUSB音声端子につながないでください。配線変更はPiの電源を切って行います。

## 他のPythonから使う

このフォルダー内で使う例です。音声は1次元float32配列、範囲は原則-1〜1です。
読み取った配列を変更せずGeminiなどの別モジュールへ渡せます。

~~~python
import config
from audio_device import AudioDevice
from microphone import Microphone
from speaker import Speaker

with AudioDevice(config.INPUT_DEVICE, config.OUTPUT_DEVICE) as audio:
    mic = Microphone(audio)
    speaker = Speaker(audio)
    mic.start()
    block = mic.read(timeout=1)
    mic.stop()
    if block is not None:
        speaker.play(block, sample_rate=mic.sample_rate)
        # playは予約のみ。プログラムをすぐ終了せず再生中は待つ／イベントを監視する。
~~~

| クラス | 主な操作 |
|---|---|
| Microphone | start(), read(timeout=0), stop(), sample_rate |
| Speaker | play(audio, sample_rate=None), stop(), is_playing |
| Ringer | start(), stop(), close(), error |
| Keypad | read_key(), close() |
| HookSwitch | is_lifted, close() |
| AudioDevice | open(), close(), status, dropped_input_blocks |

AudioDeviceは同じUSBを1つの双方向ストリームで開く共通部品です。
Microphone/Speakerを使う間だけ開き、最後にcloseします。
Speaker.stop()は待ち行列を消しますが、機器内部のバッファ分だけ音が残る場合があります。
録音は20ms単位、最大100ブロックを保持します。読み取りが遅いと新しいブロックを破棄します。
再生は最大10秒分を保持し、超過時はBufferErrorを返します。長い音声は短く分け、
再生待ちが減ってから追加してください。
hook.is_lifted と keypad.read_key() は5〜10ms程度の間隔で繰り返し呼びます。
スイッチを安定判定する間隔が必要です。Ringerの操作はメインスレッドから行います。
GPIOを共有する場合はLGPIOFactoryを1個作って各クラスに渡し、
各クラスをcloseしてからfactoryをcloseします。main.pyが具体例です。

## 検証

~~~bash
.venv/bin/python -m unittest discover -s tests -v
~~~

自動テストは音声とGPIOの代替実装を使い、レート変換、再生の中断、
録音キュー、デバウンス、キー保持・複数押し、着信音の停止を確認します。
Pi実機での音質・USB同時入出力・接点の極性は、各単体テストで確認してください。
