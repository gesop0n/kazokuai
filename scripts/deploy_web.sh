#!/usr/bin/env bash
# Terraform の output で本番向けの Web 版をビルドし、Firebase Hosting に公開する。
# プロジェクトは引数だけで決める。引数がなければ terraform も flutter も firebase も起動しない。
# Firebase のクライアント設定はビルドの引数にだけ渡し、リポジトリのファイルには書かない。
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=gcp_args.sh
source "$root/scripts/gcp_args.sh"

usage() {
  cat <<'EOF' >&2
使い方: scripts/deploy_web.sh --project=ID --state-bucket=BUCKET [--region=REGION]

プロジェクト ID と状態のバケットは、毎回引数で渡す。
Hosting の /api/** は firebase.json で asia-northeast1 のサービス kazokuai に回している。
EOF
  exit 2
}

GCP_FLAGS="project state-bucket region"
GCP_REQUIRED="$GCP_FLAGS"
parse_gcp_args "$@"

if [[ "$region" != "asia-northeast1" ]]; then
  echo "Hosting の /api/** は firebase.json で asia-northeast1 の kazokuai に回しています。リージョンが違うと Web 版は公開しません。" >&2
  exit 1
fi

export_gcp_project

terraform -chdir="$root/infra" init \
  -input=false \
  -reconfigure \
  -backend-config="bucket=${state_bucket}" \
  -backend-config="prefix=kazokuai"

out=$(mktemp)
defs=$(mktemp)
trap 'rm -f "$out" "$defs"' EXIT
terraform -chdir="$root/infra" output -json >"$out"

python3 -I - "$out" >"$defs" <<'PY'
import json, shlex, sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
names = [
    "firebase_api_key",
    "firebase_auth_domain",
    "firebase_project_id",
    "firebase_app_id",
    "firebase_messaging_sender_id",
    "firebase_storage_bucket",
    "hosting_url",
    "cloud_run_uri",
    "cloud_run_region",
    "cloud_run_service",
]
for name in names:
    if name not in data:
        sys.exit(f"terraform output に {name} がない")
    raw = data[name]
    value = raw["value"] if isinstance(raw, dict) and "value" in raw else raw
    if value is None:
        value = ""
    if not isinstance(value, str):
        sys.exit(f"terraform output の {name} が文字列ではない")
    print(f"{name}={shlex.quote(value)}")
PY

# shellcheck disable=SC1090
source "$defs"

if [[ "$firebase_project_id" != "$project" ]]; then
  echo "Terraform の firebase_project_id（${firebase_project_id}）が --project（${project}）と違います。" >&2
  exit 1
fi
if [[ "$cloud_run_region" != "asia-northeast1" || "$cloud_run_service" != "kazokuai" ]]; then
  echo "Hosting の /api/** は firebase.json で asia-northeast1 の kazokuai に回しています。output が違うと Web 版は公開しません。" >&2
  exit 1
fi

(
  cd "$root/mobile"
  flutter build web \
    --dart-define=KAZOKUAI_TARGET=production \
    --dart-define="FIREBASE_API_KEY=${firebase_api_key}" \
    --dart-define="FIREBASE_APP_ID=${firebase_app_id}" \
    --dart-define="FIREBASE_MESSAGING_SENDER_ID=${firebase_messaging_sender_id}" \
    --dart-define="FIREBASE_PROJECT_ID=${firebase_project_id}" \
    --dart-define="FIREBASE_AUTH_DOMAIN=${firebase_auth_domain}" \
    --dart-define="FIREBASE_STORAGE_BUCKET=${firebase_storage_bucket}"
)

(
  cd "$root/firebase"
  firebase deploy --only hosting --project="$project" --non-interactive
)

printf 'Web 版: %s\n' "$hosting_url"
printf '電話機がつなぐ URL: %s\n' "$cloud_run_uri"
