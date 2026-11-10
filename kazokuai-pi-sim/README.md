# かぞくAI 電話機シミュレーター

かぞくAI の電話機(Raspberry Pi 4 と受話器・キーパッド・本体スピーカー)を Windows の上に再現し、
実機向けのプログラム `kazokuai-device`(arm64)を、ビルドし直さずにそのまま動かします。

## 動作確認の手順

### 1. 用意するもの

- Windows 11(または Windows 10 22H2 以降)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  - 入れたあと一度起動し、左下が「Engine running」になるまで待ちます。
  - 設定の General で「Use the WSL 2 based engine」がオンになっていることを確かめます(既定でオンです)。
- 新しい WSL:PowerShell で `wsl --update` を一度実行しておきます(電話機の画面と音に WSLg を使います)。
- ヘッドセットかイヤホン(マイクの確認に使います)

### 2. インストールする

Docker Desktop を起動した状態で、このフォルダーの **`インストール.cmd` をダブルクリック**します。

1. `%LOCALAPPDATA%\KazokuAI` にコピーされます。
2. 「サーバーの URL」と「シークレット」の入力欄が出ます。部品の確認だけなら「あとで」で進めます。
   入れた値は、このパソコンの `%LOCALAPPDATA%\KazokuAI\secret\.env` にだけ保存されます。
3. 電話機が組み立てられて起動します。初回は 25 分ほどかかります(2 回目からは 1 分ほど)。
4. デスクトップに「かぞくAI 電話機」(起動)と「かぞくAI 電話機の設定」(URL とシークレットを変える)ができます。

終わると、電話機の画面(受話器とキーパッドの絵)が開きます。受話器はクリックか Space で上げ下げ、キーはクリックかキーボードの 0〜9 * # で押せます。

インストールせずに、このフォルダーで `powershell -ExecutionPolicy Bypass -File .\start.ps1` を実行して動かすこともできます。

### 3. 電話機の部品を確かめる(シークレットは要りません)

PowerShell で電話機のシェルに入ります。

```powershell
& "$env:LOCALAPPDATA\KazokuAI\pi.ps1"
```

電話機の中で、次を 1 つずつ実行します。止めるときは Ctrl+C です。

```bash
sudo systemctl stop kazokuai-device   # 本番の動きが動いていれば止める
kazokuai-device check devices         # 「USB PnP Sound Device」と「本体スピーカー (PAM8012)」が出る
kazokuai-device check hook            # 画面の受話器を上げ下げすると「上がっている / 置かれている」と出る
kazokuai-device check keypad          # 画面のキーを押すと「キー: 5」のように出る
kazokuai-device check ringer          # 本体スピーカーから呼び出し音(プルル…)が鳴り、画面の穴が光る
kazokuai-device check speaker         # 受話器(Windows のスピーカー)にテスト音が出る
kazokuai-device check mic             # 画面の受話器を上げてから話すと、録音して再生する
```

`pisim status` で、GPIO の値や本体スピーカーの周波数も見られます。

### 4. 本番の動きを確かめる(サーバーの URL とシークレットが要ります)

URL とシークレットは提出物に含めていません(値は別にお知らせします)。
保存先の `secret\.env` には、次の 2 つだけを書きます。受話器や GPIO の設定(実機の `.env` の下半分)は、シミュレーターの値が入っているので書きません。

```ini
KAZOKUAI_BACKEND=https://…run.app
PHONE_SECRET=…
```

`KAZOKUAI_BACKEND` は `kazokuai-device -backend` に、`PHONE_SECRET` は環境変数としてそのまま渡ります(サーバーには `Kazokuai-Secret` ヘッダーで届きます)。
インストールのときに入れなかった場合は、デスクトップの「かぞくAI 電話機の設定」で入れます。保存すると、本番の動きが新しい値で起動し直します。

様子は次で見られます。

```powershell
docker exec kazokuai-pi journalctl -fu kazokuai-device
```

URL とシークレットが空のあいだは、本番の動きは起動しません。

### 5. 止める・消す

- 止める:`docker compose down`(中身は残り、デスクトップの「かぞくAI 電話機」でまた起動できます)
- 消す:`%LOCALAPPDATA%\KazokuAI\アンインストール.cmd` をダブルクリック(URL とシークレットを残すかを聞きます)

### うまくいかないとき

| 症状 | 対処 |
|---|---|
| 「Docker が動いていません」と出る | Docker Desktop を起動し、「Engine running」になってから、もう一度 `start.ps1` |
| 電話機の画面が開かない | `wsl --update` のあと PC を再起動し、もう一度 `start.ps1` |
| 音が出ない・マイクが拾わない | Windows の既定のスピーカーとマイク(設定 → システム → サウンド)を確かめる。マイクは「設定 → プライバシーとセキュリティ → マイク」で「デスクトップ アプリがマイクにアクセスできるようにする」をオンにする。画面の受話器を置いているあいだは、受話器の音は消してあります |
| `check` で「GPIO … を開けなかった」と出る | 本番の動きが GPIO を使っています。`sudo systemctl stop kazokuai-device` |

### 確認する人の PC に加わる変更について

- コンテナは特権モード(`privileged`、ホストのネットワーク)で動きます。GPIO と無線のまねに要るためです。
- 起動中は、arm64 のプログラムを qemu で動かす設定(binfmt_misc)が Docker Desktop の中に登録されます。Docker Desktop を再起動すると消えます。
- 電話機の無線(wlan0)のため、Docker Desktop の Linux のカーネルにモジュールを読み込みます(Docker Desktop を再起動すると外れます)。

---

ここから下は、シミュレーターの仕組みと細かい使い方です。

## 概要

Windows の WSL2 に、電話機の中身(Raspberry Pi 4 と、受話器・キーパッド・本体スピーカー)を作ります。
中身は Debian で、ラズパイと同じ Linux の口(`/dev/gpiochip0`、`/sys/class/pwm`、ALSA / PulseAudio)が見えます。
ラズパイ向けのプログラムは書き換えずに、ここに置いて動かせます。

| 実機 | シミュレーター |
|---|---|
| Raspberry Pi 4 Model B(Raspberry Pi OS 64 ビット) | WSL2 の Debian(名前 `kazokuai-pi`、ホスト名 `kazokuai`) |
| 受話器のスイッチ(GPIO5、上げると GND に閉じる) | 画面の受話器をクリック、または Space |
| キーパッド(行 17/27/22/23、列 24/25/4 のマトリクス) | 画面のキーを押しているあいだ閉じる(キーボードの 0〜9 * # でも可) |
| 本体スピーカー(GPIO18 → PAM8012 → 8Ω) | GPIO18 の PWM の波形をそのまま音にして Windows のスピーカーで鳴らす |
| 受話器のマイクとスピーカー(USB オーディオ) | 「USB PnP Sound Device」という機器として、Windows のマイクとスピーカーにつなぐ |
| 有線 LAN(eth0) | 電話機の中の eth0(10.77.0.2)。PC のネットワークに NAT でつながる |
| 無線 LAN(wlan0) | mac80211_hwsim の本物の無線の機器。PC 側に立てた Wi-Fi「kazokuai-home」に `nmcli` でつなぐ |
| 日本語の Raspberry Pi OS(ロケール ja_JP.UTF-8、タイムゾーン Asia/Tokyo) | 同じ。メッセージも日付も日本語・日本時間で出る |

配線の番号は、GitHub の `tel-base`(`device/phone-hardware/config.py`)と `ticket/118`(`device/pi/README.md`)に合わせてあります。

## 動かし方は 2 つ

- **Docker 版(配る人向け)**: Docker Desktop があれば `start.ps1` だけで動きます。
- **WSL 版**: WSL に Debian の電話機を直接作ります(`install.ps1`)。

どちらも中身は同じです(同じ `setup.sh` で用意します)。

## Docker 版

### 要るもの

- Windows 11(または Windows 10 22H2 以降)
- Docker Desktop(設定の General で「Use the WSL 2 based engine」がオンのもの)
- WSLg が使える WSL2(`wsl --update` で新しくしておく)
- ヘッドセットかイヤホン(スピーカーで鳴らすと、AI が自分の声を聞いてしまうことがあります)

### 起動する

このフォルダーで PowerShell を開いて実行します。

```powershell
powershell -ExecutionPolicy Bypass -File .\start.ps1
```

初回はイメージを作るので 15 分ほど(GPIO 対応の qemu を作るため)、さらに電話機の無線(wlan0)のモジュールを作るので 10 分ほどかかります(2 回目からは作りません)。
起動すると、電話機の画面が開きます。

| やること | 方法 |
|---|---|
| 電話機のシェルを開く | `.\pi.ps1`(`.\pi.ps1 pisim status` のようにコマンドも渡せる) |
| ファイルを置く | このフォルダーの `share` に置くと、電話機の `~/share` に見える |
| 止める | `docker compose down` |
| 作り直す | `docker compose down -v` で中身ごと消してから `start.ps1` |

電話機のユーザーは `tana` で、パスワードなしで `sudo` できます。

### しくみ(Docker 版)

コンテナの中で systemd を動かし、WSL 版と同じサービス(`pisim`、`pisim-net`、NetworkManager、電話機の画面)を起動します。
GPIO のまね、`/sys` の差し替え、無線のカーネルモジュールのために、コンテナは特権(`privileged`)と `network_mode: host` で動きます。
電話機の eth0 と wlan0 は、コンテナの中に作るネットワーク名前空間 `kazokuai` に入れるので、WSL や Docker のネットワークには手を入れません。
画面と音は WSLg(`/run/desktop/mnt/host/wslg`)を使います。

## WSL 版

### 要るもの

- Windows 11(または Windows 10 22H2 以降)と、WSLg が使える WSL2(`wsl --update` で新しくしておく)
- ヘッドセットかイヤホン(スピーカーで鳴らすと、AI が自分の声を聞いてしまうことがあります)

### 入れ方

このフォルダーで PowerShell を開いて実行します。途中でユーザー(既定は `tana`)のパスワードを聞かれます。

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
# ユーザー名を変えるとき: .\install.ps1 -User pi
```

数分で終わります。デスクトップに「かぞくAI 電話機」ができます。

## 使い方

### 電話機の画面

デスクトップの「かぞくAI 電話機」で開きます。画面には電話機だけが出ます。
受話器をクリックすると上がり、もう一度クリックすると置きます(Space でも)。キーは押しているあいだだけ閉じます(キーボードの 0〜9 * # でも)。
呼び出し音が鳴っているあいだは、本体スピーカーの穴が光ります。GPIO の値などは、電話機のシェルで `pisim status` を実行すると見られます。

### 電話機のシェル

Windows Terminal の `kazokuai-pi`、または `wsl -d kazokuai-pi` で入ります。プロンプトは `tana@kazokuai` です。
このシェルから起動したプログラムだけが、電話機の GPIO を使えます(下の「仕組み」)。

```bash
pisim status             # GPIO と部品の今の状態
gpiodetect               # gpiochip0 [pinctrl-bcm2711] (58 lines)
gpioinfo -c gpiochip0    # libgpiod 2 で線の一覧(Raspberry Pi OS trixie と同じ書き方)
```

### ファイルを置く

どちらでも置けます。

- エクスプローラーで `\\wsl.localhost\kazokuai-pi\home\tana` を開いて、ドラッグする
- PowerShell から scp(実機の `scp ... tana@kazokuai.local:~/` の代わり。ポートは 2222)

  ```powershell
  scp -P 2222 "D:\Downloads\phone-hardware.zip" tana@localhost:~/
  ```

### 例: tel-base の Python(device/phone-hardware)

実機の README のとおりに動きます。`python3-gpiozero` と `python3-lgpio` は入れてあります。

```bash
unzip phone-hardware.zip && cd phone-hardware
python3 -m venv --system-site-packages .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python main.py devices
.venv/bin/python main.py ringer   # 本体スピーカーでプルルル
.venv/bin/python main.py keypad   # 画面のキーを押す
.venv/bin/python main.py hook     # 画面の受話器を上げ下げする
```

`config.py` の `INPUT_DEVICE` / `OUTPUT_DEVICE` は、`main.py devices` に出る `USB_PnP_Sound_Device` にします(番号は実機と違います)。

### kazokuai-device(実機向けの arm64 のバイナリをそのまま動かす)

このフォルダーに置いた `kazokuai-device`(Raspberry Pi 向けの arm64 のバイナリ)を、ビルドし直さずにそのまま動かします。
arm64 のプログラムは、GPIO の ioctl を通すようにした qemu(`build-qemu-gpio.sh` で Debian の qemu のソースから作る)を通って動きます。
arm64 版の libc と PulseAudio のライブラリも入れてあるので、受話器と本体スピーカーの音も実機と同じように扱えます。

部品の確認は、電話機のシェルで実行します(サービスが動いているときは、先に `sudo systemctl stop kazokuai-device` で止めます)。

```bash
kazokuai-device check devices   # 音声の機器の一覧
kazokuai-device check hook      # 画面の受話器を上げ下げする
kazokuai-device check keypad    # 画面のキーを押す
kazokuai-device check ringer    # 本体スピーカーで呼び出し音
kazokuai-device check speaker   # 受話器にテスト音
kazokuai-device check mic       # 受話器を上げてから話す
```

本番の動き(サーバーにつないで電話を受ける)には、サーバーの URL とシークレットなどが要ります。これらは提出物に含めず、使う人が `secret/.env` に書きます。

- `start.ps1` が初回に空の `secret/.env` を作ります。`.dockerignore` と `.gitignore` で外してあるので、イメージにも Git にも入りません。
- コンテナには `/etc/kazokuai/secret/.env` として読み取り専用で渡り、`kazokuai-device` のサービスが `/etc/kazokuai/device.env` に続けて読みます。
- `secret/.env` に値が 1 つも無いあいだ、サービスは起動しません。書いたら次で読み直します。

  ```powershell
  docker exec kazokuai-pi systemctl restart kazokuai-device
  docker exec kazokuai-pi journalctl -fu kazokuai-device
  ```

WSL 版では、`sudo nano /etc/kazokuai/secret/.env` に書いて `sudo systemctl restart kazokuai-device` します。
電話機の ID と鍵(`/var/lib/kazokuai/phone.json`)は、Docker 版では名前つきのボリュームに置くので、作り直しても変わりません。

### 例: Go のデバイスをこの中でビルドする(device/pi)

この中で x86_64 向けにビルドし直すこともできます(cgo の gcc は入れてあります。Go 1.27 は mise などで入れます)。

```bash
go build -o device ./device
./device check hook
```

systemd のサービスで動かすときは、`ExecStart` の前に `pisim exec --user tana --` を付けます。

```ini
ExecStart=/usr/local/bin/pisim exec --user tana -- /usr/local/bin/device
```

## 配線を変える

`/etc/kazokuai-pisim.conf` を書き換えて、`sudo systemctl restart pisim-net pisim NetworkManager` で読み直します。

```ini
HOOK_GPIO=5
LIFTED_WHEN_CLOSED=true

ROW_GPIO=17,27,22,23
COL_GPIO=24,25,4
KEYS=123 456 789 *0#

RINGER_GPIO=18
AUDIO_NAME=USB PnP Sound Device
VOLUME=0.6

WIFI=true
WIFI_SSID=kazokuai-home
WIFI_PASSWORD=kazokuai-wifi

PULSE_SERVER=unix:/mnt/wslg/PulseServer
```

番号はどれも BCM の番号です。既定は tel-base の `config.py` と `device/pi/README.md` と同じです。

| 項目 | 意味 |
|---|---|
| `HOOK_GPIO` | 受話器のスイッチ(フック)の GPIO |
| `LIFTED_WHEN_CLOSED` | 受話器を上げると接点が閉じるなら `true`、開くなら `false` |
| `ROW_GPIO` / `COL_GPIO` | キーパッドのマトリクスの行(上から)と列(左から)の GPIO |
| `KEYS` | キーの並び。上の行から、行ごとに空白で区切る |
| `RINGER_GPIO` | 本体スピーカー(PAM8012)につながる PWM の GPIO |
| `AUDIO_NAME` | 受話器の USB オーディオの名前(`KAZOKUAI_AUDIO_DEVICE` に入れる名前) |
| `VOLUME` | 本体スピーカーの音量(0〜2) |
| `WIFI` / `WIFI_SSID` / `WIFI_PASSWORD` | 電話機の wlan0 と、PC 側に立てる Wi-Fi のアクセスポイント(SSID は 1〜32 バイト、パスワードは 8〜63 文字) |
| `PULSE_SERVER` | 音を出す PulseAudio(WSLg) |

## 日本語

- ロケールは `ja_JP.UTF-8`、タイムゾーンは `Asia/Tokyo` です(WSL 版の時刻は Windows に合わせて WSL が決めます)。日本語のファイル名もそのまま扱えます。
- 画面の文字には Noto Sans CJK JP を使います。
- `pisim status` の表は、全角の文字の幅に合わせて揃えます。
- `install.ps1`・`start.ps1`・`pi.ps1` は、Windows のコンソールの文字コードを UTF-8 にしてから動くので、日本語のフォルダー名の下に置いても、電話機の中の日本語の出力も化けません。

## 仕組み

- **GPIO**: WSL のカーネルには GPIO のシミュレーター(gpio-sim)が無いので、`pisim` がユーザー空間で `/dev/gpiochip0`(pinctrl-bcm2711、58 本)をまねます。電話機のシェル(`pisim-shell`)は seccomp で GPIO の ioctl だけを `pisim` に回し、`pisim` がカーネルの代わりに答えます。GPIO 文字デバイスの v2 と v1 の両方に答えるので、lgpio / gpiozero、libgpiod、go-gpiocdev がそのまま動きます。
- **電気のふるまい**: 線ごとの向き・出力・プル(電源投入時は GPIO0〜8 が上、9〜27 が下)と、フックとキーの接点から、各線の値を計算します。行を 1 本ずつ Low にして列を読むマトリクスの読み取りも、デバウンスとエッジのイベントも実機と同じです。
- **本体スピーカー**: GPIO18 の High / Low の切り替わりを時刻つきで受け取り、48kHz に積分して、分圧(10kΩ / 1kΩ)→ 入力コンデンサー → PAM8012 → 小さな 8Ω スピーカーの順に通して鳴らします。lgpio のソフトウェア PWM でも、`/sys/class/pwm`(pwmchip0 の pwm0 = GPIO18)でも鳴ります。
- **受話器**: WSLg の PulseAudio に、`USB PnP Sound Device` という名前のスピーカーとマイクを作ります(使えればエコーキャンセル付き)。受話器を置いているあいだは消音します。
- **ネットワーク**: WSL のディストリビューションはどれも同じ WSL の eth0 を使うので、そこには手を入れません。電話機のためにネットワーク名前空間 `kazokuai` を作り、Raspberry Pi 4 と同じく `eth0` と `wlan0` を入れます(`pisim-net.service`)。
  - `eth0` は veth で、PC 側の `pisim0`(10.77.0.1)から NAT で PC の LAN に出ます。
  - `wlan0` は `mac80211_hwsim` の無線の機器です。`iw`、`nmcli`、NetworkManager がそのまま使えます。PC 側の無線 `pisimap0` で hostapd が Wi-Fi のアクセスポイントを立て、dnsmasq が DHCP を配ります。mac80211_hwsim は、無線を作ったネットワーク名前空間が同じ無線どうししか電波が届かないので、2 つとも PC 側で作ってから、電話機の無線だけを `kazokuai` に移します。
  - NetworkManager と wpa_supplicant は、systemd の設定でこの名前空間の中で動きます。`/sys` を読み取り専用にして、udev が無くても(Docker 版)機器を扱えるようにしています。`/etc/resolv.conf` は書き換えません。

  ```bash
  nmcli dev wifi list
  sudo nmcli dev wifi connect kazokuai-home password kazokuai-wifi
  ```
- **ラズパイらしさ**: 電話機のシェルの中では、次のように見えます。
  - `/proc/cpuinfo` の最後に、64 ビット版の Raspberry Pi OS と同じ `Revision`(c03114)・`Serial`・`Model`(Raspberry Pi 4 Model B Rev 1.4)の行が足される。gpiozero はこれで機種を「4B」と判断する
  - `/sys/bus/gpio` と `/sys/dev/char` が gpiochip0 に合う。gpiochip0 と同じ番号(1:7)の `/dev/full` は隠すので、`gpiodetect` には gpiochip0 だけが出る
  - ホスト名は `kazokuai`(Docker 版でも)
  - シリアル番号と、eth0・wlan0 の MAC アドレス(Raspberry Pi の `dc:a6:32`)は、起動し直しても変わらない
  - ユーザーは Raspberry Pi OS と同じグループ(`gpio`、`i2c`、`spi`、`dialout`、`plugdev` など)に入る

## 実機と違うところ

- CPU は x86_64 です。arm64 のバイナリは qemu で CPU をまねて動くので、実機より遅くなります(GPIO と音は問題なく動くことを確かめてあります)。
- arm64 を qemu で動かす登録(binfmt_misc)は、カーネル全体に効きます。Docker 版では Docker Desktop の、WSL 版では WSL のほかのディストリビューションでも、arm64 のファイルはこの qemu で動きます。登録は WSL を止めると消え、電話機を起動するたびに `pisim-arm64.service` が登録し直します。
- GPIO を使えるのは、電話機のシェル(Windows Terminal、`wsl -d kazokuai-pi`、ssh)と `pisim exec` から起動したプログラムだけです。`wsl -e` で直接起動したものからは見えません。
- `pisim` を起動し直しても、開いている電話機のシェルからは GPIO を使い続けられます(systemd に預けておく)。ただし、そのとき動いていたプログラムは起動し直します。
- 線の情報の変化の通知(`gpioinfo --watch` など)は届きません。
- 次のものはありません。`/dev/gpiochip1`(raspberrypi-exp-gpio)、`/proc/device-tree`、`/dev/gpiomem`、`/sys/class/gpio`、`/boot/firmware/config.txt`、`vcgencmd`・`pinctrl`・`raspi-config`。
- 音は WSLg を通るので、実機より少し遅れます。
- WSL のカーネルには `mac80211_hwsim` が入っていないので、`setup.sh` が初回に Microsoft のカーネルのソースからこのモジュールと、Docker の中では読み込めない依存のモジュール(`cfg80211`、`mac80211`、`libarc4`、WPA2 に使う `ccm` と `cmac`)を作ります(`build-wifi-module.sh`、10 分ほど)。作ったモジュールはシンボルの版を持たないので `insmod -f` で読み込み、カーネルは tainted になります。`wsl --update` でカーネルが変わったら、`sudo bash /usr/local/share/kazokuai-pisim/build-wifi-module.sh` をもう一度動かします(Docker 版は起動するたびに足りないものだけを作ります)。作れないときは、有線の eth0 だけになります(`pisim status` に理由が出ます)。
- 無線の国の設定(regulatory.db)は、カーネルが WSL 自身のファイルから読もうとして見つけられないので、世界共通の設定で動きます(チャンネル 6 なので困りません)。
- 見える Wi-Fi は、PC 側に立てた 1 つだけです。電話機の中で待ち受けたポートには、Windows の localhost からは届きません。
- Bluetooth はありません。

## ファイル

| ファイル | 中身 |
|---|---|
| `start.ps1` / `pi.ps1` / `compose.yaml` / `Dockerfile` | Docker 版を起動する / 電話機のシェルを開く |
| `install.ps1` | WSL 版: WSL に Debian を入れ、`setup.sh` を動かす |
| `setup.sh` | Debian の中を用意する(パッケージ、pisim、ユーザー、systemd、音声の設定) |
| `build-wifi-module.sh` | wlan0 に使う `mac80211_hwsim` を、WSL のカーネルのソースから作る |
| `build-qemu-gpio.sh` | GPIO の ioctl を通す qemu-aarch64 を、Debian の qemu のソースから作る |
| `kazokuai-device` | 実機向けの arm64 のバイナリ(あれば `/usr/local/bin` に入れ、サービスにする) |
| `secret/.env` | サーバーの URL やシークレット。提出物には含めず、インストーラーか `start.ps1` が作る |
| `インストール.cmd` / `アンインストール.cmd` / `installer/` | インストーラー(コピー、設定の入力欄、デスクトップのショートカット、アンインストール) |
| `bin/pisim` | 電話機のラズパイ(linux/amd64。`pisim/` からビルドしたもの) |
| `pisim/` | `pisim` の Go のソース(標準ライブラリだけ。`CGO_ENABLED=0 go build -o ../bin/pisim .`) |
| `gui/kazokuai-phone.py` | 電話機の画面(tkinter) |
| `files/` | systemd のユニット、配線の設定、ALSA、ssh、デスクトップのエントリー |
