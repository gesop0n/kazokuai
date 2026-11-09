#!/usr/bin/env bash
# debian:bookworm の linux/arm64 で電話機をビルドする。
# malgo は cgo が要る。Ubuntu 24.04 の glibc で作ると、Raspberry Pi OS (bookworm) で動かないことがある。
set -euo pipefail

arch=$(uname -m)
if [[ "$arch" != "aarch64" ]]; then
  echo "このビルドは linux/arm64 で動かします。今は ${arch} です。" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential ca-certificates curl

# go.mod の Go と同じにする。チェックサムは https://go.dev/dl/?mode=json の linux-arm64。
tarball=go1.27.3.linux-arm64.tar.gz
go_sha=a06e99309dbcbdca1a8ccd2282c3ee146e55930886e26b4f1193269587165f49
if ! /usr/local/go/bin/go version 2>/dev/null | grep -q "go1.27.3 "; then
  tmp=$(mktemp)
  curl -fsSL -o "$tmp" "https://go.dev/dl/${tarball}"
  echo "${go_sha}  ${tmp}" | sha256sum -c -
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tmp"
  rm -f "$tmp"
fi

export PATH="/usr/local/go/bin:${PATH}"
export CGO_ENABLED=1
export GOOS=linux
export GOARCH=arm64
export GOTOOLCHAIN=local

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
go build -trimpath -buildvcs=false -ldflags="-s -w" -o kazokuai-device ./device
# 空白 2 つでファイル名を続ける。macOS の shasum -c は、sha256sum -b の * をファイル名の一部として読む。
sha256sum kazokuai-device > kazokuai-device.sha256

if [[ -n "${BUILD_UID:-}" && -n "${BUILD_GID:-}" ]]; then
  chown "${BUILD_UID}:${BUILD_GID}" kazokuai-device kazokuai-device.sha256
fi
