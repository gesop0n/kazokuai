#!/usr/bin/env bash
# 今のコミットの電話機を、ログインせずに受け取れるプレリリースとして出す。
# 名前はコミット ID の先頭 7 桁。タグは pi- と 40 桁のコミット ID。
set -euo pipefail

if [[ ! "${GITHUB_SHA:-}" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "GITHUB_SHA は 40 桁のコミット ID です。" >&2
  exit 1
fi
if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "GITHUB_REPOSITORY がありません。" >&2
  exit 1
fi
if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "GH_TOKEN がありません。" >&2
  exit 1
fi
if [[ ! -f kazokuai-device || ! -f kazokuai-device.sha256 ]]; then
  echo "実行ファイルか sha256 がありません。先にビルドしてください。" >&2
  exit 1
fi

short=${GITHUB_SHA:0:7}
tag="pi-${GITHUB_SHA}"
notes="pi-release の ${GITHUB_SHA} でビルドした、電話機の linux/arm64 の実行ファイルです。"

if gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  gh release upload "$tag" --repo "$GITHUB_REPOSITORY" --clobber \
    kazokuai-device kazokuai-device.sha256
else
  gh release create "$tag" --repo "$GITHUB_REPOSITORY" \
    --title "$short" \
    --prerelease \
    --notes "$notes" \
    kazokuai-device kazokuai-device.sha256
fi
