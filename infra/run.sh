#!/usr/bin/env bash
# plan と apply。プロジェクトは引数だけで決める。
# 環境変数に別のプロジェクトがあっても、引数がなければ terraform を起動しない。
set -euo pipefail

usage() {
  cat <<'EOF' >&2
使い方: infra/run.sh plan|apply --project=ID --billing-account=ID --image=IMAGE --state-bucket=BUCKET [--region=REGION]

プロジェクト ID、請求先アカウント、イメージ、状態のバケットは、毎回引数で渡す。
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

if [[ $# -lt 1 ]]; then
  usage
fi

command=$1
shift

case "$command" in
  plan | apply) ;;
  *) usage ;;
esac

project=""
billing_account=""
image=""
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
    --image)
      image="${2-}"
      shift 2 || usage
      ;;
    --image=*)
      image="${1#*=}"
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
reject "image" "$image"
reject "state-bucket" "$state_bucket"
reject "region" "$region"

if [[ "$state_bucket" == */* ]]; then
  echo "state-bucket はバケット名だけです。gs:// や / は付けません。" >&2
  exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)

export GOOGLE_PROJECT="$project"
export GOOGLE_CLOUD_PROJECT="$project"
export CLOUDSDK_CORE_PROJECT="$project"
export GOOGLE_BILLING_PROJECT="$project"
export TF_IN_AUTOMATION=1
export TF_INPUT=0
unset TF_VAR_project_id TF_VAR_region TF_VAR_billing_account TF_VAR_container_image

terraform -chdir="$root/infra" init \
  -input=false \
  -reconfigure \
  -backend-config="bucket=${state_bucket}" \
  -backend-config="prefix=kazokuai"

terraform -chdir="$root/infra" "$command" \
  -input=false \
  -var="project_id=${project}" \
  -var="region=${region}" \
  -var="billing_account=${billing_account}" \
  -var="container_image=${image}"
