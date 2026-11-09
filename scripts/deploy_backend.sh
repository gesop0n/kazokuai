#!/usr/bin/env bash
# コンテナを linux/amd64 で作り、Artifact Registry に上げ、そのイメージで Terraform を適用する。
# プロジェクトは引数だけで決める。引数がなければ docker も gcloud も terraform も起動しない。
set -euo pipefail

usage() {
  cat <<'EOF' >&2
使い方: scripts/deploy_backend.sh --project=ID --billing-account=ID --state-bucket=BUCKET [--region=REGION]

プロジェクト ID、請求先アカウント、状態のバケットは、毎回引数で渡す。
イメージのタグは、この実行の時刻と git のリビジョンから作る。
EOF
  exit 2
}

reject() {
  local name=$1
  local value=$2
  if [[ -z "$value" || "$value" =~ [[:space:]] || "$value" == -* ]]; then
    echo "${name} が空か、空白を含むか、- で始まっています。" >&2
    exit 2
  fi
}

project=""
billing_account=""
state_bucket=""
region="asia-northeast1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      project="${2-}"
      shift 2 || usage
      ;;
    --project=*)
      project="${1#*=}"
      shift
      ;;
    --billing-account)
      billing_account="${2-}"
      shift 2 || usage
      ;;
    --billing-account=*)
      billing_account="${1#*=}"
      shift
      ;;
    --state-bucket)
      state_bucket="${2-}"
      shift 2 || usage
      ;;
    --state-bucket=*)
      state_bucket="${1#*=}"
      shift
      ;;
    --region)
      region="${2-}"
      shift 2 || usage
      ;;
    --region=*)
      region="${1#*=}"
      shift
      ;;
    -h | --help) usage ;;
    *)
      echo "不明な引数: $1" >&2
      usage
      ;;
  esac
done

reject "project" "$project"
reject "billing-account" "$billing_account"
reject "state-bucket" "$state_bucket"
reject "region" "$region"

if [[ "$state_bucket" == */* ]]; then
  echo "state-bucket はバケット名だけです。gs:// や / は付けません。" >&2
  exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
stamp=$(date -u +%Y%m%d%H%M%S)
tag=$stamp
if sha=$(git -C "$root" rev-parse --short=12 HEAD 2>/dev/null); then
  tag="${stamp}-${sha}"
fi
# Cloud Run は linux/amd64 のイメージを動かす。
image="${region}-docker.pkg.dev/${project}/kazokuai/backend:${tag}"

export GOOGLE_PROJECT="$project"
export GOOGLE_CLOUD_PROJECT="$project"
export CLOUDSDK_CORE_PROJECT="$project"
export GOOGLE_BILLING_PROJECT="$project"
unset TF_VAR_project_id TF_VAR_region TF_VAR_billing_account TF_VAR_container_image

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
