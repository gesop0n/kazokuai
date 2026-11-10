#!/usr/bin/env bash
# main で追跡しているファイルを、提出先の作業ツリーへ写す。
# 提出先の .git と LICENSE は残す。.github/workflows は写さない。
# 秘密があれば push しない。
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

# コミットメッセージは、写すたびに人が決める。
if [[ -z "${SUBMISSION_MESSAGE:-}" ]]; then
  echo "SUBMISSION_MESSAGE にコミットメッセージを入れてください。" >&2
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

# 提出先では Actions は動かない。workflows を入れると Contents の権限では push できない。
rm -rf "$dest/.github/workflows"
if [[ -d "$dest/.github" ]] && [[ -z $(find "$dest/.github" -mindepth 1 -print -quit) ]]; then
  rmdir "$dest/.github"
fi

if ! python3 -I "$root/scripts/scan_secrets.py" "$dest"; then
  echo "秘密の形をした文字列があるため、提出先へは送りません。" >&2
  exit 1
fi

git -C "$dest" -c core.autocrlf=false add -A
if git -C "$dest" diff --cached --quiet; then
  echo "変更はないので、コミットしません。"
  exit 0
fi

export GIT_TERMINAL_PROMPT=0
git -C "$dest" \
  -c user.name='github-actions[bot]' \
  -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  -c commit.gpgsign=false \
  commit -m "$SUBMISSION_MESSAGE"
git -C "$dest" push origin HEAD:main
