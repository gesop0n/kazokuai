#!/usr/bin/env bash
# コンテナを linux/amd64 で作り、Artifact Registry に上げ、gcloud run deploy で新しいリビジョンにする。
# Terraform は適用しない。プロジェクトは引数だけで決める。引数がなければ docker も gcloud も起動しない。
# 環境変数、秘密、CPU、インスタンス数は渡さない。今のサービスに残っているものを使う。
# タグは付けない。タグを付けると、次の terraform plan がリビジョンの差分を出す。
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=gcp_args.sh
source "$root/scripts/gcp_args.sh"

# Hosting の /api/** と Terraform のサービス名と揃える。
service=kazokuai

usage() {
  cat <<'EOF' >&2
使い方: scripts/deploy_backend.sh --project=ID [--region=REGION]

プロジェクト ID は、毎回引数で渡す。
イメージのタグは、この実行の時刻と git のリビジョンから作る。
Cloud Run のサービス kazokuai が既にあるときに、その新しいリビジョンとして載せる。
EOF
  exit 2
}

GCP_FLAGS="project region"
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
printf 'イメージ: %s\n' "$image"

# サービスが無いときに gcloud run deploy は、秘密もインスタンス数も無いサービスを作ってしまう。
if ! uri=$(gcloud run services describe "$service" \
  --project="$project" \
  --region="$region" \
  --format='value(status.url)'); then
  echo "Cloud Run のサービス ${service} が ${region} にありません。先に mise run infra:apply で作ります。" >&2
  exit 1
fi

gcloud run deploy "$service" \
  --project="$project" \
  --region="$region" \
  --image="$image" \
  --quiet

printf '電話機がつなぐ URL: %s\n' "$uri"
