#!/usr/bin/env bash
# 電話機の実行ファイルと systemd のユニットを入れ、有効にして起動する。
# 引数に linux/arm64 の実行ファイルを渡すと、ビルドしない。
# 渡さないと、この機械の上で cgo を有効にしてビルドする。
# DEVICE_INSTALL_ROOT はテストがインストール先を差し替える。Pi では空のままにする。
set -euo pipefail

usage() {
  cat <<'EOF' >&2
使い方: mise run device:install [-- <実行ファイル>]

実行ファイルのパスを渡すと、ビルドせずにそれを入れます。
渡さないと、この機械の上で Go を使って linux/arm64 向けにビルドします。
設定は /etc/kazokuai/device.env です。見本を、まだファイルが無いときだけコピーします。
EOF
  exit 2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi
if [[ "${1:-}" == "--" ]]; then
  shift
fi
if [[ $# -gt 1 ]]; then
  usage
fi

repo=$(cd "$(dirname "$0")/.." && pwd)
prefix=${DEVICE_INSTALL_ROOT:-}
bin_dir="${prefix}/usr/local/bin"
unit_dir="${prefix}/etc/systemd/system"
env_file="${prefix}/etc/kazokuai/device.env"
installed="${bin_dir}/kazokuai-device"

run_priv() {
  if [[ -n "$prefix" || "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_as() {
  local mode=$1 src=$2 dest=$3
  run_priv mkdir -p "$(dirname "$dest")"
  if [[ -n "$prefix" ]]; then
    install -m "$mode" "$src" "$dest"
  else
    run_priv install -m "$mode" -o root -g root "$src" "$dest"
  fi
}

# systemd の EnvironmentFile と同じく、前後の空白と対の二重引用符を外して値を読む。
read_value() {
  local file=$1 key=$2 value
  value=$(run_priv awk -v key="$key" '
    $0 ~ "^" key "=" { value = substr($0, length(key) + 2) }
    END { printf "%s", value }
  ' "$file")
  value=${value%$'\r'}
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ ${#value} -ge 2 && "$value" == \"*\" && "$value" == *\" ]]; then
    value=${value:1:${#value}-2}
  fi
  printf '%s' "$value"
}

is_linux_arm64_elf() {
  local hex
  hex=$(od -An -t x1 -N 20 "$1" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
  [[ ${#hex} -ge 40 \
    && "${hex:0:8}" == "7f454c46" \
    && "${hex:8:2}" == "02" \
    && "${hex:10:2}" == "01" \
    && "${hex:36:4}" == "b700" ]]
}

if [[ $# -eq 1 && ! -f "$1" ]]; then
  echo "実行ファイルが見つかりません: $1" >&2
  exit 1
fi

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

if [[ $# -eq 0 ]]; then
  cc=${CC:-gcc}
  if ! command -v "$cc" >/dev/null 2>&1; then
    echo "ビルドには C コンパイラが要ります（cgo）。sudo apt install -y build-essential" >&2
    exit 1
  fi
  if ! command -v go >/dev/null 2>&1; then
    echo "Go がありません。Pi の上でビルドするときは、先に mise install go を動かしてください。" >&2
    exit 1
  fi
  (
    cd "$repo"
    export CGO_ENABLED=1
    export GOOS=linux
    export GOARCH=arm64
    export GOTOOLCHAIN=local
    go build -trimpath -buildvcs=false -ldflags="-s -w" -o "$stage/kazokuai-device" ./device
  )
  binary="$stage/kazokuai-device"
else
  binary=$1
fi

if ! is_linux_arm64_elf "$binary"; then
  echo "実行ファイルが linux/arm64 の ELF ではありません: $binary" >&2
  exit 1
fi

install_as 0755 "$binary" "$installed"
install_as 0644 "$repo/device/pi/kazokuai-device.service" "${unit_dir}/kazokuai-device.service"
if ! run_priv test -e "$env_file"; then
  install_as 0640 "$repo/device/pi/device.env" "$env_file"
fi

person=$(read_value "$env_file" KAZOKUAI_WATCHED_PERSON)
backend=$(read_value "$env_file" KAZOKUAI_BACKEND)
if [[ -z "$person" || "$person" == *[[:space:]]* ]]; then
  echo "見守る方の ID が空か、空白を含みます。${env_file} の KAZOKUAI_WATCHED_PERSON を書いてから、もう一度動かしてください。" >&2
  exit 1
fi
if [[ -z "$backend" || "$backend" == *[[:space:]]* ]]; then
  echo "バックエンドの URL が空か、空白を含みます。${env_file} の KAZOKUAI_BACKEND を書いてから、もう一度動かしてください。" >&2
  exit 1
fi

run_priv systemctl daemon-reload
run_priv systemctl enable kazokuai-device.service
run_priv systemctl restart kazokuai-device.service
echo "電話機を入れて起動しました。"
