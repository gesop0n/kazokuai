# 電話機を Pi に入れる

新しい SD カードから電話機を作り直す手順です。配線、安全、設定、部品の確認、OS、起動時に動かす設定、実行ファイルの受け取り方をここにまとめます。

Pi を触るのは人です。指揮役は Pi に入りません。実行ファイルは、人が `pi-release` を main から早送りして push すると、GitHub Actions が作ります。Pi の上でビルドするのは予備です。

## この実行ファイル

Linux の実行ファイルは、バックエンドへつなぎ、切れたら自分でつなぎ直します。起動時に動き、失敗したら動き直します。再起動のあとも、systemd が起動し、ひとりでにバックエンドへつなぎます。

受話器は、`KAZOKUAI_AUDIO_DEVICE` に書いた名前の USB オーディオを開きます。音には `KAZOKUAI_SPEAKER_GAIN` を掛け、`KAZOKUAI_SPEAKER_LIMIT` を超えた分を切ります。フックは GPIO で読みます。呼び出し音は GPIO18 をソフトウェアで切り替え、本体のスピーカーを鳴らします。`config.txt` は変えません。ランプは、まだ光を出さず、ログに「ランプが点きました。」と書きます。キーパッドの読み取りは、まだこの実行ファイルにはありません。

macOS で手元から動かすときは、既定のマイクとスピーカー、Enter キーのフックのままです。ここから下は Pi の手順です。

## OS と Wi-Fi

[Raspberry Pi Imager](https://www.raspberrypi.com/software/) で書きます。機種は Raspberry Pi 4 Model B、OS は Raspberry Pi OS Lite（64 ビット）の bookworm にします。ビルドに使う `debian:bookworm` と glibc が揃います。bookworm で作った実行ファイルは、より新しい glibc（Trixie など）の上でも動きます。Imager の一覧に bookworm が無いときは、Lite の 64 ビットを選び、この README のビルドと同じ世代かどうかを確認してください。

Imager の設定で、次を入れます。

- ホスト名: `kazokuai`
- ユーザー: `kazokuai`（パスワードは人が決める）
- Wi-Fi の SSID とパスワード
- SSH を有効にする

書いたカードを Pi に挿して電源を入れ、別のパソコンから `ssh kazokuai@kazokuai.local` で入れることを確認します。

## 配線

電源を切ってから配線します。受話器のスピーカーとマイクは、動作を確認してある USB オーディオアダプターにつなぎます。1 つのアダプターを、マイクと受話口の両方に使います。キーパッドは 3 列 4 行です。表に無い端子（C4、VSS、そのほか）はつなぎません。番号は BCM です。

| 用途 | BCM 番号 | 物理ピン |
|---|---|---|
| キー R1 / R2 / R3 / R4 | 17 / 27 / 22 / 23 | 11 / 13 / 15 / 16 |
| キー C1 / C2 / C3 | 24 / 25 / 4 | 18 / 22 / 7 |
| 呼び出し音 | 18 | 12 |
| 受話器スイッチ | 5 | 29 |
| スイッチのもう片方 | GND | 30 |

キーの並びの既定は、上の行から `1 2 3`、`4 5 6`、`7 8 9`、`* 0 #` です。5 以外は実機で確かめてから使います。複数のキーが同時に押されているあいだは、全部離すまで入力にしません。この読み取りは、まだこの実行ファイルにはありません。

同じ GPIO を、同時に 2 つのプログラムで使わないでください。

## 安全

受話器スイッチは、元の電話回路から電気的に切り離した無電圧接点にします。切替接点のときは、使わない側も含めて接点の組全体を切り離します。GPIO に電話回線や元の基板の電圧を加えないでください。この電話機は、上げると接点が開きます。既定と見本の `KAZOKUAI_LIFTED_WHEN_CLOSED` は `false` です。違いは、下の `check hook` で確かめます。

呼び出し音は PAM8012（入力コンデンサーを内蔵したモジュールを想定）です。

- GPIO18 → 10kΩ → 分岐点 → IN+
- 分岐点 → 1kΩ → GND
- V+ は 5V。GND と IN− は Pi の GND
- SPK+ と SPK− は、本体の 8Ω スピーカーだけにつなぐ
- SPK− を GND や USB の音声端子につなげない

音は、倍率を掛けたあと、上限を超えた分だけを切ります。既定は倍率 `0.15`、上限 `0.1` です。tel-base の倍率 0.5 は、音全体を上限まで縮めるときの値です。ソフトの振幅制限は、耳元の音圧を保証しません。音の出る確認は、受話器を耳から離してから始めます。

スピーカーを開けないときは、Raspberry Pi OS（bookworm）で次を入れます。malgo は実行時に `libasound.so.2` を開きます。

```bash
sudo apt install -y libasound2
```

## 設定

見本は `device/pi/device.env` です。本物は Pi の `/etc/kazokuai/device.env` だけに置きます。合言葉は、人がそのファイルに書きます。見本の合言葉は空です。値をリポジトリに写しません。

人が入れる項目です。

| 変数 | 見本 | 意味 |
|---|---|---|
| `KAZOKUAI_BACKEND` | `http://localhost:8080` | バックエンドの URL。https は wss でつなぐ。Pi では、届くアドレスに書き換える。localhost は Pi 自身 |
| `PHONE_SECRET` | 空 | 合言葉。電話機を登録するときだけ使う。Cloud Run ではバックエンドと同じものを、このファイルにだけ書く。空なら手元の開発用の合言葉 |
| `KAZOKUAI_PHONE_FILE` | 空 | ID と鍵のファイル。空なら `/var/lib/kazokuai/phone.json` |
| `KAZOKUAI_AUDIO_DEVICE` | 空 | USB アダプターの名前の一部。音声を開くときは要る。番号は再起動や接続の順で変わるので、名前で選ぶ |

Linux の実行ファイルが読む、受話器、フック、呼び出し音の既定です。空の項目は、この既定のまま動きます。音声の名前だけは、空だと開けません。

| 変数 | 既定 | 意味 |
|---|---|---|
| `KAZOKUAI_MIC_CHANNEL` | `0` | マイクのチャンネル。最初が 0 |
| `KAZOKUAI_SPEAKER_GAIN` | `0.15` | スピーカーの音に掛ける倍率。0 より大きく 4 以下 |
| `KAZOKUAI_SPEAKER_LIMIT` | `0.1` | フルスケールに対する上限。0 より大きく 1 以下 |
| `KAZOKUAI_GPIO_CHIP` | `gpiochip0` | GPIO のチップ |
| `KAZOKUAI_HOOK_GPIO` | `5` | フックの BCM 番号 |
| `KAZOKUAI_RINGER_GPIO` | `18` | 呼び出し音の BCM 番号 |
| `KAZOKUAI_LIFTED_WHEN_CLOSED` | `false` | 上げると接点が閉じるなら true、開くなら false。この電話機は開く |
| `KAZOKUAI_HOOK_DEBOUNCE` | `50ms` | フックが安定したとみなす時間 |

起動すると、電話機は最初の起動で ID と鍵を作り、`/var/lib/kazokuai/phone.json` に残します。権限は 0600 で、電話機を動かすユーザーだけが読めます。合言葉で登録したあと、WebSocket、トークン、電話の報告には、この ID と鍵を付けます。結び付くまでは待って、つながったままにします。アプリで同期すると、その見守る方の電話を受けます。バックエンドがこの ID を知らないときは、同じ ID と鍵でもう一度登録します。このファイルを消すと別の ID を作るので、残します。

Mac では、ユーザーの設定ディレクトリの `kazokuai/phone.json` です。

## 部品の確認

実行ファイルを入れたあと、電話機の上で部品を 1 つずつ確かめます。終わるまで続くものは Ctrl+C で止めます。音の出る確認は、受話器を耳から離してから始めます。確認は sudo なしで動かします。

`device check` は `/etc/kazokuai/device.env` があれば、systemd の EnvironmentFile と同じ規則で読みます。サービスも同じファイルを使います。同じ名前の環境変数があれば、空でもそちらを使います。空なら、その項目は既定に戻ります。

```bash
/usr/local/bin/kazokuai-device check devices
```

`check` のうしろを、次のどれかに替えます。

| コマンド | 動作 |
|---|---|
| `device check devices` | 音声の機器の名前を並べる |
| `device check speaker` | 受話器で 1 秒の音を鳴らす |
| `device check mic` | 5 秒録って、受話器から流す |
| `device check hook` | 受話器が上がっているか、置かれているかを出す |
| `device check ringer` | 止めるまで、本体のスピーカーを鳴らす |

`devices` で見た名前の、他の機器と重ならない一部を `KAZOKUAI_AUDIO_DEVICE` に入れます。`hook` で、上げると接点が閉じるかを見ます。違うときは `KAZOKUAI_LIFTED_WHEN_CLOSED` を変えます。

## Pi に道具を入れる

実行ファイルは外で作ります。ユニットと設定の見本はリポジトリから入れるので、入れる直前に、配ったのと同じコミットを Pi に置きます。checkout は、プレリリースのタグが決まってからにします。先に git と mise だけ入れておけます。Go は、予備の Pi 上ビルドのときだけ入れます。`mise install` を引数なしで動かすと、linux/arm64 の無い Flutter なども取りにいって失敗します。

```bash
sudo apt install -y git
curl https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
source ~/.bashrc
```

## 実行ファイルを配る

配布ブランチは `pi-release` です。main から早送りするだけで、このブランチに直接コミットしません。push は、Pi ではないパソコンで、人が行います。

ブランチがまだ無いとき:

```bash
git fetch origin
git switch main
git pull --ff-only
git switch -c pi-release
git push -u origin pi-release
```

すでにあるとき:

```bash
git fetch origin
git switch pi-release
git merge --ff-only origin/main
git push origin pi-release
```

早送りできないときは、`pi-release` に main 以外のコミットがあります。合わせ方を決めるまで push しません。

push すると、GitHub Actions がランナー `ubuntu-24.04-arm` の上で、`debian:bookworm` のコンテナの中で linux/arm64 をビルドします。malgo は cgo が要るので、cgo を有効にします。Ubuntu 24.04 の glibc は Raspberry Pi OS（bookworm）より新しいので、ランナーの OS では直接ビルドしません。できた実行ファイルと sha256 は、公開のプレリリースになります。ログインしなくても URL から落とせます。名前（タイトル）はコミット ID の先頭 7 桁、タグは `pi-` と 40 桁のコミット ID です。

進行は <https://github.com/gesop0n/kazokuai/actions> で見ます。タグは、ビルドしたコミットを指します。再実行で同じコミットのリリースがすでにあるときは、ファイルを差し替えます。

## 別のパソコンから入れる

プレリリースのタグは、次の API で探します。`prerelease` で、タグが `pi-` で始まる最新の 1 件です。ブラウザで見るときは <https://github.com/gesop0n/kazokuai/releases> です。

落としたファイルは、sha256 が一致してから Pi へ送ります。ファイルの中身は `sha256sum` の形式です。ハッシュ、空白 2 つ、ファイル名です。macOS の `shasum -a 256 -c` と、GNU の `sha256sum -c` の両方が読めます。

### macOS

```bash
tag=$(python3 - <<'PY'
import json, urllib.request
url = "https://api.github.com/repos/gesop0n/kazokuai/releases?per_page=30"
with urllib.request.urlopen(url) as response:
    releases = json.load(response)
for release in releases:
    name = release.get("tag_name") or ""
    if release.get("prerelease") and name.startswith("pi-"):
        print(name)
        break
else:
    raise SystemExit("pi- のプレリリースがありません")
PY
)
echo "$tag"
curl -fsSL -o kazokuai-device "https://github.com/gesop0n/kazokuai/releases/download/${tag}/kazokuai-device"
curl -fsSL -o kazokuai-device.sha256 "https://github.com/gesop0n/kazokuai/releases/download/${tag}/kazokuai-device.sha256"
shasum -a 256 -c kazokuai-device.sha256
scp kazokuai-device kazokuai@kazokuai.local:~/
```

URL を直接書くときは、`https://github.com/gesop0n/kazokuai/releases/download/pi-<40桁>/kazokuai-device` です。sha256 のファイルは、同じタグの `kazokuai-device.sha256` です。

### Windows の PowerShell

```powershell
$releases = Invoke-RestMethod "https://api.github.com/repos/gesop0n/kazokuai/releases?per_page=30"
$tag = @($releases | Where-Object { $_.prerelease -and $_.tag_name.StartsWith("pi-") } | Select-Object -First 1).tag_name
if (-not $tag) { throw "pi- のプレリリースがありません" }
Write-Output $tag
$base = "https://github.com/gesop0n/kazokuai/releases/download/$tag"
Invoke-WebRequest "$base/kazokuai-device" -OutFile kazokuai-device
Invoke-WebRequest "$base/kazokuai-device.sha256" -OutFile kazokuai-device.sha256
$expected = (Get-Content .\kazokuai-device.sha256 -Raw).Split()[0].ToLower()
$actual = (Get-FileHash .\kazokuai-device -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $expected) { throw "sha256 が一致しません" }
scp .\kazokuai-device kazokuai@kazokuai.local:~/
```

### Pi の上で入れる

sudo がパスワードを聞けるように、`-t` を付けて入ります。直前に表示されたタグ（`pi-` と 40 桁のコミット ID）を、そのまま checkout してから入れます。

```bash
ssh -t kazokuai@kazokuai.local
git clone https://github.com/gesop0n/kazokuai.git
cd kazokuai
git switch --detach "<表示されたタグ>"
mise trust
mise run --skip-tools device:install -- ~/kazokuai-device
```

2 回目以降は、clone の代わりに `git fetch origin` と、同じ `git switch --detach` を使います。

最初の 1 回は、見本を `/etc/kazokuai/device.env` に置き（権限 0640）、実行ファイルを入れ、サービスを有効にして起動します。すでにファイルがあるときは上書きしません。電話機が ID と鍵を作り、合言葉で登録してから、その ID と鍵でつなぎます。見守る方は、アプリから同期して決めます。ファイルの場所と権限は、上の「設定」に書きました。

`KAZOKUAI_AUDIO_DEVICE` が空のままだと、サービスは音声を開けずに動き直します。機器の名前を見てから、設定を書きます。

```bash
/usr/local/bin/kazokuai-device check devices
sudoedit /etc/kazokuai/device.env
```

書くものは、バックエンドの URL、合言葉、音声の機器名です。受話器、フック、呼び出し音の残りの項目は、既定のまま残します。見守る方は、アプリから同期します。

保存したら、同じコマンドをもう一度動かします。

```bash
mise run --skip-tools device:install -- ~/kazokuai-device
```

サービスを動かし直します。環境ファイルの `PHONE_SECRET` はプロセスの環境に入り、コマンドラインには出ません。

再起動して、ひとりでに戻ることを確認します。

```bash
sudo reboot
```

起動したあと、もう一度入って次を見ます。`active` のまま、`バックエンドとの接続が切れたので` が繰り返されなければ、つながっています。その文が繰り返されるときは、URL と合言葉を見ます。`音声の機器の名前が要ります` や `スピーカーを開けなかった` と出るときは、機器名と `libasound2` を見ます。

```bash
systemctl status kazokuai-device
journalctl -u kazokuai-device -f
```

## 入れ直す

新しいコミットを配るときは、main を `pi-release` へ早送りして push し、Actions が終わるのを待ちます。新しい実行ファイルと sha256 を落とし、一致を確認してから Pi のホームへ送ります。Pi では配ったコミットを checkout し、`mise run --skip-tools device:install -- ~/kazokuai-device` を動かします。`/etc/kazokuai/device.env` はそのまま残します。見本に項目が増えたときは、足りない行だけ人が足します。

すでに入れてある Pi で、人が `systemctl edit` で足した上書きは消してかまいません。`User=` と `XDG_RUNTIME_DIR` は、ユニット自体に書かれます。上書きが残っていると、そちらのほうが優先されます。入れ直したあとに、上書きを消してサービスを動かし直します。

```bash
sudo systemctl revert kazokuai-device
sudo systemctl restart kazokuai-device
```

## 予備: 自分でビルドする

配布の実行ファイルを使わないときだけ、ここで作ります。どちらも cgo が要ります。`CGO_ENABLED=0` では `./device` をビルドできません。

### Pi の上

Pi は linux/arm64 です。この機械の上で作ります。

```bash
sudo apt install -y build-essential
cd ~/kazokuai
mise install go
mise run --skip-tools device:install
```

引数を付けないので、mise の Go でビルドしてから入れます。設定ファイルの扱いは、実行ファイルを渡したときと同じです。

### Pi の外

arm64 の `debian:bookworm` の中で作ります。スクリプトは、中の `uname -m` が `aarch64` でなければ、パッケージを入れる前に止まります。Apple Silicon の Docker では `--platform linux/arm64` で足ります。

```bash
docker run --rm --platform linux/arm64 \
  -e "BUILD_UID=$(id -u)" \
  -e "BUILD_GID=$(id -g)" \
  -v "$PWD:/src" -w /src \
  debian:bookworm \
  bash device/pi/bookworm-build.sh
```

リポジトリのルートに `kazokuai-device` と `kazokuai-device.sha256` ができます。この 2 つはコミットしません。sha256 を確認し、`kazokuai-device` を Pi へ送って、`mise run --skip-tools device:install -- ~/kazokuai-device` に渡します。

## サービス

ユニットは `device/pi/kazokuai-device.service` です。`EnvironmentFile` で `/etc/kazokuai/device.env` を読みます。

- 実行ファイルは `/usr/local/bin/kazokuai-device`。引数は `--backend` だけです。電話機は ID と鍵でつなぎ、同期はアプリから行います
- `StateDirectory=kazokuai` で `/var/lib/kazokuai` を、入れた人のユーザーの所有で作ります。ID と鍵のファイルはそこです
- `Restart=on-failure`、`RestartSec=5`、起動回数の上限は切りません
- ネットワークが来てから起動し、多ユーザー起動で有効になります
- 入れた人のユーザーで動きます。インストールが `User=` と、そのユーザーの `XDG_RUNTIME_DIR` を書きます。root では、その人の PipeWire が見えず、音声を開けません
- ユーザーは `KAZOKUAI_SERVICE_USER`、無ければ `SUDO_USER`、それも無ければ今のユーザーです
- インストールは `loginctl enable-linger` で、起動したときからそのユーザーの PipeWire を動かします
- GPIO の線には `gpio` グループが要ります。入っていなければ、インストールが `sudo usermod -aG gpio <ユーザー>` を出します。動かしてから入り直してください
- 停止信号は SIGINT です。プロセスが扱うのがこちらのためです

ファイルの項目は、すべてプロセスの環境に入ります。`KAZOKUAI_BACKEND` が空、または空白を含むときは、ファイルは置いたままサービスを起動しません。電話機は自分の ID と鍵で起動します。設定ディレクトリ `/etc/kazokuai` は 0755 で、入れた人が通過できます。設定ファイルは、そのユーザーのグループが読める 0640 です。合言葉は、他のユーザーからは読めません。ID と鍵のファイルは 0600 で、サービスを動かすユーザーだけが読めます。

## tel-base

配線と安全の注意は、この README に移しました。この仕様のチケットがマージされたあと、`tel-base` ブランチは人が消します。指揮役は、頼まれずに他人のブランチを消しません。
