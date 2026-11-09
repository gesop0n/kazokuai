#!/usr/bin/env bash
# コンテナを linux/amd64 で作り、Artifact Registry に上げ、そのイメージで Terraform を適用する。
# プロジェクトは引数だけで決める。引数がなければ docker も gcloud も terraform も起動しない。
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=gcp_args.sh
source "$root/scripts/gcp_args.sh"

usage() {
  cat <<'EOF' >&2
使い方: scripts/deploy_backend.sh --project=ID --billing-account=ID --state-bucket=BUCKET [--region=REGION]

プロジェクト ID、請求先アカウント、状態のバケットは、毎回引数で渡す。
イメージのタグは、この実行の時刻と git のリビジョンから作る。
EOF
  exit 2
}

GCP_FLAGS="project billing-account state-bucket region"
GCP_REQUIRED="$GCP_FLAGS"
parse_gcp_args "$@"
stamp=$(date -u +%Y%m%d%H%M%S)
tag=$stamp
if sha=$(git -C "$root" rev-parse --short=12 HEAD 2>/dev/null); then
  tag="${stamp}-${sha}"
fi
# Cloud Run は linux/amd64 のイメージを動かす。
image="${region}-docker.pkg.dev/${project}/kazokuai/backend:${tag}"

export_gcp_project

docker build --platform linux/amd64 -t "$image" "$root"
gcloud auth configure-docker "${region}-docker.pkg.dev" --quiet
docker push "$image"

"$root/infra/run.sh" apply \
  --project="$project" \
  --billing-account="$billing_account" \
  --image="$image" \
  --state-bucket="$state_bucket" \
  --region="$region"

uri=$(terraform -chdir="$root/infra" output -raw cloud_run_uri)
printf 'イメージ: %s\n' "$image"
printf '電話機がつなぐ URL: %s\n' "$uri"
