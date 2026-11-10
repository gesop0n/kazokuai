#!/usr/bin/env bash
# main で追跡しているファイルを、提出先の作業ツリーへ写す。
# 提出先の .git と LICENSE は残す。秘密があれば push しない。
# トークンは表示しない。提出先の認証は、workflow の checkout が済ませる。
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)

if [[ "${1:-}" == "check-token" ]]; then
  if [[ -z "${SUBMISSION_TOKEN:-}" ]]; then
    echo "SUBMISSION_TOKEN がありません。gh secret set SUBMISSION_TOKEN --repo gesop0n/kazokuai で登録してください。" >&2
    exit 1
  fi
  exit 0
fi

if [[ $# -ne 0 ]]; then
  echo "使い方: scripts/submit_snapshot.sh [check-token]" >&2
  exit 2
fi

if [[ ! "${GITHUB_SHA:-}" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "GITHUB_SHA は 40 桁のコミット ID です。" >&2
  exit 1
fi

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "GITHUB_REPOSITORY がありません。" >&2
  exit 1
fi

source_dir=${SOURCE_DIR:-$root}
dest=${SUBMISSION_DIR:-$root/submission}

if [[ "$source_dir" -ef "$dest" ]]; then
  echo "提出先と写す元が同じです。" >&2
  exit 1
fi

if [[ ! -d "$dest/.git" && ! -f "$dest/.git" ]]; then
  echo "提出先の作業ツリーがありません。" >&2
  exit 1
fi

if [[ ! -f "$dest/LICENSE" ]]; then
  echo "提出先に LICENSE がありません。" >&2
  exit 1
fi

license=$(mktemp)
trap 'rm -f "$license"' EXIT
cp "$dest/LICENSE" "$license"

find "$dest" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

(
  cd "$source_dir" || exit
  git archive HEAD
) | tar -x -C "$dest"
cp "$license" "$dest/LICENSE"

if ! python3 -I "$root/scripts/scan_secrets.py" "$dest"; then
  echo "秘密の形をした文字列があるため、提出先へは送りません。" >&2
  exit 1
fi

git -C "$dest" -c core.autocrlf=false add -A
if git -C "$dest" diff --cached --quiet; then
  echo "変更はないので、コミットしません。"
  exit 0
fi

short=${GITHUB_SHA:0:7}
export GIT_TERMINAL_PROMPT=0
git -C "$dest" \
  -c user.name='github-actions[bot]' \
  -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  -c commit.gpgsign=false \
  commit -m "${GITHUB_REPOSITORY} の ${short} を写す"
git -C "$dest" push origin HEAD:main
