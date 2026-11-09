# 電話機を Pi に入れる

新しい SD カードから電話機を作り直す手順です。配線、OS、起動時に動かす設定、実行ファイルの受け取り方をここにまとめます。

Pi を触るのは人です。指揮役は Pi に入りません。実行ファイルは、人が `pi-release` を main から早送りして push すると、GitHub Actions が作ります。Pi の上でビルドするのは予備です。

## 今の実行ファイルでできること

今の実行ファイルは、バックエンドへつなぎ、切れたら自分でつなぎ直します。起動時に動き、失敗したら動き直します。再起動のあとも、systemd が起動し、ひとりでにバックエンドへつなぎます。

受話器の GPIO、フック、キーパッド、呼び出し音、音量の倍率は、まだこの実行ファイルにはありません。それらは #118 がマージされたあと、この README と `/etc/kazokuai/device.env` の見本に足します。今のフックはキーボードの Enter なので、systemd の下では受話器の上げ下げになりません。通話そのものは、その部品が入ってから Pi の上で確認します。

起動時にスピーカーを開きます。開けないとプロセスは終わり、systemd が動き直します。ログに「スピーカーを開けなかった」と出たら、下の「音声」を見てください。

## OS と Wi-Fi

[Raspberry Pi Imager](https://www.raspberrypi.com/software/) で書きます。OS は Raspberry Pi OS Lite（64 ビット）の bookworm にします。ビルドに使う `debian:bookworm` と glibc が揃います。bookworm で作った実行ファイルは、より新しい glibc（Trixie など）の上でも動きます。Imager の一覧に bookworm が無いときは、Lite の 64 ビットを選び、この README のビルドと同じ世代かどうかを確認してください。

Imager の設定で、次を入れます。

- ホスト名: `kazokuai`
- ユーザー: `kazokuai`（パスワードは人が決める）
- Wi-Fi の SSID とパスワード
- SSH を有効にする

書いたカードを Pi に挿して電源を入れ、別のパソコンから `ssh kazokuai@kazokuai.local` で入れることを確認します。

## PWM の 1 行

呼び出し音は GPIO18 のハードウェア PWM を使います。Raspberry Pi OS の bookworm と Trixie では、設定ファイルは `/boot/firmware/config.txt` です。電源を切ってからカードを別のパソコンに挿すか、Pi の上で編集します。

ファイルの末尾に、次の 1 行だけ足します。

```
dtoverlay=pwm
```

既定のピンは GPIO18 です。保存して再起動します。`/sys/class/pwm` が見えれば足ります。見えないときだけ、同じファイルに `dtparam=audio=off` を足して再起動します。アナログ音声が PWM を使っているときの切り分けです。最初から足す行ではありません。

## 配線

電源を切ってから配線します。受話器のスピーカーとマイクは、動作を確認してある USB オーディオアダプターにつなぎます。キーパッドは 3 列 4 行です。表に無い端子（C4、VSS、そのほか）はつなぎません。

| 用途 | BCM 番号 | 物理ピン |
|---|---|---|
| キー R1 / R2 / R3 / R4 | 17 / 27 / 22 / 23 | 11 / 13 / 15 / 16 |
| キー C1 / C2 / C3 | 24 / 25 / 4 | 18 / 22 / 7 |
| 呼び出し音 | 18 | 12 |
| 受話器スイッチ | 5 | 29 |
| スイッチのもう片方 | GND | 30 |

複数のキーが同時に押されているあいだは、全部離すまで入力にしません。

受話器スイッチは、元の電話回路から電気的に切り離した無電圧接点にします。切替接点のときは、使わない側も含めて接点の組全体を切り離します。GPIO に電話回線や元の基板の電圧を加えないでください。上げると接点が閉じる向きを既定にします。開く向きの設定は、プログラムが読むようになってから見本に足します。

呼び出し音は PAM8012（入力コンデンサーを内蔵したモジュールを想定）です。

- GPIO18 → 10kΩ → 分岐点 → IN+
- 分岐点 → 1kΩ → GND
- V+ は 5V。GND と IN− は Pi の GND
- SPK+ と SPK− は、本体の 8Ω スピーカーだけにつなぐ
- SPK− を GND や USB の音声端子につなげない

### 音量

仕様の音量は、音に 0.15 を掛け、フルスケールの 0.1 を超えた分を切る、です。tel-base の確認は倍率 0.5 から始めていました。今の実行ファイルは、どちらの倍率もまだ掛けません。ソフトの振幅制限は、耳元の音圧を保証しません。音を確認するときは、耳から離します。

### 音声

実行ファイルは malgo で既定の再生装置を開きます。装置の名前で選ぶ設定は、まだ見本にありません。USB オーディオアダプターを挿し、それが既定の再生装置になるようにします。

スピーカーを開けないときは、Raspberry Pi OS（bookworm）で次を入れます。malgo は実行時に `libasound.so.2` を開きます。

```bash
sudo apt install -y libasound2
```

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

進行は <https://github.com/gesop0n/kazokuai/actions> で見ます。再実行で同じコミットのリリースがすでにあるときは、ファイルを差し替えます。

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

最初の 1 回は、見本を `/etc/kazokuai/device.env` に置き（権限 0640）、見守る方の ID が空なので終了コード 1 で終わります。サービスはまだ有効にしません。すでにファイルがあるときは上書きしません。合言葉は、そのファイルの中にだけ書きます。

```bash
sudoedit /etc/kazokuai/device.env
```

書くものは次の 3 つです。見本の合言葉と ID は空です。値をリポジトリに写しません。

- `KAZOKUAI_BACKEND`: Pi から届くバックエンドの URL。`https://…` の Cloud Run、または同じ LAN の URL。`http://localhost:8080` は Pi 自身です。Pi の上ではバックエンドになりません。
- `KAZOKUAI_WATCHED_PERSON`: 見守る方の ID。家族がアプリで見守る方を登録したとき、バックエンドのログに `--watched-person` に続けて出ます。その文字列を写します。見本やこの README には書きません。
- `PHONE_SECRET`: 合言葉。Cloud Run のバックエンドと同じものを、Pi のこのファイルにだけ書きます。手元の demo 用バックエンドで、バックエンド側も空のまま開発用の合言葉を使うときだけ、空のままにします。

保存したら、同じコマンドをもう一度動かします。

```bash
mise run --skip-tools device:install -- ~/kazokuai-device
```

ユニットを入れ、サービスを有効にし、起動します。環境ファイルの `PHONE_SECRET` はプロセスの環境に入り、コマンドラインには出ません。

再起動して、ひとりでに戻ることを確認します。

```bash
sudo reboot
```

起動したあと、もう一度入って次を見ます。`active` のまま、`バックエンドとの接続が切れたので` が繰り返されなければ、つながっています。その文が繰り返されるときは、URL と合言葉を見ます。スピーカーを開けないと、その前にプロセスが終わり、systemd が動き直します。

```bash
systemctl status kazokuai-device
journalctl -u kazokuai-device -f
```

## 入れ直す

新しいコミットを配るときは、main を `pi-release` へ早送りして push し、Actions が終わるのを待ちます。新しい実行ファイルと sha256 を落とし、一致を確認してから Pi のホームへ送ります。Pi では配ったコミットを checkout し、`mise run --skip-tools device:install -- ~/kazokuai-device` を動かします。`/etc/kazokuai/device.env` はそのまま残します。

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

## サービスが読む設定

見本は `device/pi/device.env` です。本物は Pi の `/etc/kazokuai/device.env` だけに置きます。ユニットは `device/pi/kazokuai-device.service` で、このファイルを `EnvironmentFile` として読みます。

- 実行ファイルは `/usr/local/bin/kazokuai-device`
- `Restart=on-failure`、`RestartSec=5`、起動回数の上限は切りません
- ネットワークが来てから起動し、多ユーザー起動で有効になります
- root で動きます。あとの GPIO と PWM を、追加の権限なしで使えるようにするためです
- 停止信号は SIGINT です。今のプロセスが扱うのがこちらのためです

`KAZOKUAI_WATCHED_PERSON` か `KAZOKUAI_BACKEND` が空、または空白を含むときは、ファイルは置いたままサービスを起動しません。

## tel-base

配線と安全の注意は、この README に移しました。この仕様のチケットがマージされたあと、`tel-base` ブランチは人が消します。指揮役は、頼まれずに他人のブランチを消しません。
