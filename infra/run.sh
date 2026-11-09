#!/usr/bin/env bash
# plan と apply。プロジェクトは引数だけで決める。
# 環境変数に別のプロジェクトがあっても、引数がなければ terraform を起動しない。
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../scripts/gcp_args.sh
source "$root/scripts/gcp_args.sh"

# --bootstrap が作る資源。Cloud Run と、それに依存する公開の IAM は入れない。
bootstrap_targets=(
  google_project_service.api
  google_artifact_registry_repository.backend
  google_secret_manager_secret.gemini_api_key
  google_secret_manager_secret.phone_shared_secret
  google_service_account.backend
  google_project_iam_member.backend_firestore
  google_secret_manager_secret_iam_member.backend_gemini
  google_secret_manager_secret_iam_member.backend_phone
  google_project_service_identity.run
  google_artifact_registry_repository_iam_member.run_reader
  google_firestore_database.default
  google_firebaserules_ruleset.firestore
  google_firebaserules_release.firestore
  google_firebase_web_app.web
  google_firebase_hosting_site.web
  google_firebase_hosting_site.published
  google_billing_budget.monthly
)

usage() {
  cat <<'EOF' >&2
使い方: infra/run.sh plan|apply --project=ID --billing-account=ID --image=IMAGE --state-bucket=BUCKET [--region=REGION]
        infra/run.sh apply --bootstrap --project=ID --billing-account=ID --image=IMAGE --state-bucket=BUCKET
        infra/run.sh apply --allow-replace --project=ID --billing-account=ID --image=IMAGE --state-bucket=BUCKET
        infra/run.sh untaint --project=ID --state-bucket=BUCKET [--region=REGION]

プロジェクト ID、請求先アカウント、イメージ、状態のバケットは、毎回引数で渡す。
--bootstrap は Cloud Run と、その公開の IAM を作らない。
--allow-replace は、この 1 回だけ Cloud Run の削除の保護を外す。
untaint は、状態に残った google_cloud_run_v2_service.backend の tainted を外す。
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

command=$1
shift

case "$command" in
  plan | apply | untaint) ;;
  *) usage ;;
esac

bootstrap=0
allow_replace=0
rest=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bootstrap)
      bootstrap=1
      shift
      ;;
    --allow-replace)
      allow_replace=1
      shift
      ;;
    *)
      rest+=("$1")
      shift
      ;;
  esac
done

if [[ "$bootstrap" -eq 1 && "$allow_replace" -eq 1 ]]; then
  echo "--bootstrap と --allow-replace は一緒に付けません。" >&2
  exit 2
fi
if [[ "$command" == "untaint" && ("$bootstrap" -eq 1 || "$allow_replace" -eq 1) ]]; then
  echo "untaint には --bootstrap と --allow-replace を付けません。" >&2
  exit 2
fi
if [[ "$command" == "plan" && "$allow_replace" -eq 1 ]]; then
  echo "--allow-replace は apply に付けます。" >&2
  exit 2
fi

if [[ "$command" == "untaint" ]]; then
  GCP_FLAGS="project state-bucket region"
  GCP_REQUIRED="project state-bucket region"
else
  GCP_FLAGS="project billing-account image state-bucket region"
  GCP_REQUIRED="project billing-account image state-bucket region"
fi

parse_gcp_args "${rest[@]}"

export_gcp_project
export TF_IN_AUTOMATION=1
export TF_INPUT=0

terraform -chdir="$root/infra" init \
  -input=false \
  -reconfigure \
  -backend-config="bucket=${state_bucket}" \
  -backend-config="prefix=kazokuai"

if [[ "$command" == "untaint" ]]; then
  terraform -chdir="$root/infra" untaint google_cloud_run_v2_service.backend
  exit 0
fi

args=(
  -input=false
  -var="project_id=${project}"
  -var="region=${region}"
  -var="billing_account=${billing_account}"
  -var="container_image=${image}"
)
if [[ "$allow_replace" -eq 1 ]]; then
  args+=(-var="deletion_protection=false")
fi
if [[ "$bootstrap" -eq 1 ]]; then
  for target in "${bootstrap_targets[@]}"; do
    args+=("-target=${target}")
  done
fi

terraform -chdir="$root/infra" "$command" "${args[@]}"
