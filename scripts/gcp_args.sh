# プロジェクトの引数を読む。source してから parse_gcp_args を呼ぶ。
# 呼び出し側が usage を定義する。
# GCP_FLAGS は受け付ける名前、GCP_REQUIRED は空を拒む名前。どちらも空白区切り。
# 読んだ値は project, billing_account, image, state_bucket, region と、
# firebase_api_key, firebase_auth_domain, firebase_app_id,
# firebase_messaging_sender_id, firebase_project_id, firebase_storage_bucket に入る。
# region の既定は asia-northeast1。firebase_storage_bucket は空でもよい。

reject_gcp_value() {
  local name=$1
  local value=$2
  if [[ -z "$value" || "$value" =~ [[:space:]] || "$value" == -* ]]; then
    echo "${name} が空か、空白を含むか、- で始まっています。" >&2
    exit 2
  fi
}

gcp_flag_allowed() {
  local name=$1
  local item
  for item in ${GCP_FLAGS}; do
    if [[ "$item" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

parse_gcp_args() {
  if [[ -z "${GCP_FLAGS-}" || -z "${GCP_REQUIRED-}" ]]; then
    echo "GCP_FLAGS と GCP_REQUIRED を決めてから引数を読んでください。" >&2
    exit 2
  fi

  project=""
  billing_account=""
  image=""
  state_bucket=""
  region="asia-northeast1"
  firebase_api_key=""
  firebase_auth_domain=""
  firebase_app_id=""
  firebase_messaging_sender_id=""
  firebase_project_id=""
  firebase_storage_bucket=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)
        gcp_flag_allowed project || {
          echo "不明な引数: $1" >&2
          usage
        }
        project="${2-}"
        shift 2 || usage
        ;;
      --project=*)
        gcp_flag_allowed project || {
          echo "不明な引数: $1" >&2
          usage
        }
        project="${1#*=}"
        shift
        ;;
      --billing-account)
        gcp_flag_allowed billing-account || {
          echo "不明な引数: $1" >&2
          usage
        }
        billing_account="${2-}"
        shift 2 || usage
        ;;
      --billing-account=*)
        gcp_flag_allowed billing-account || {
          echo "不明な引数: $1" >&2
          usage
        }
        billing_account="${1#*=}"
        shift
        ;;
      --image)
        gcp_flag_allowed image || {
          echo "不明な引数: $1" >&2
          usage
        }
        image="${2-}"
        shift 2 || usage
        ;;
      --image=*)
        gcp_flag_allowed image || {
          echo "不明な引数: $1" >&2
          usage
        }
        image="${1#*=}"
        shift
        ;;
      --state-bucket)
        gcp_flag_allowed state-bucket || {
          echo "不明な引数: $1" >&2
          usage
        }
        state_bucket="${2-}"
        shift 2 || usage
        ;;
      --state-bucket=*)
        gcp_flag_allowed state-bucket || {
          echo "不明な引数: $1" >&2
          usage
        }
        state_bucket="${1#*=}"
        shift
        ;;
      --region)
        gcp_flag_allowed region || {
          echo "不明な引数: $1" >&2
          usage
        }
        region="${2-}"
        shift 2 || usage
        ;;
      --region=*)
        gcp_flag_allowed region || {
          echo "不明な引数: $1" >&2
          usage
        }
        region="${1#*=}"
        shift
        ;;
      --firebase-api-key)
        gcp_flag_allowed firebase-api-key || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_api_key="${2-}"
        shift 2 || usage
        ;;
      --firebase-api-key=*)
        gcp_flag_allowed firebase-api-key || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_api_key="${1#*=}"
        shift
        ;;
      --firebase-auth-domain)
        gcp_flag_allowed firebase-auth-domain || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_auth_domain="${2-}"
        shift 2 || usage
        ;;
      --firebase-auth-domain=*)
        gcp_flag_allowed firebase-auth-domain || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_auth_domain="${1#*=}"
        shift
        ;;
      --firebase-app-id)
        gcp_flag_allowed firebase-app-id || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_app_id="${2-}"
        shift 2 || usage
        ;;
      --firebase-app-id=*)
        gcp_flag_allowed firebase-app-id || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_app_id="${1#*=}"
        shift
        ;;
      --firebase-messaging-sender-id)
        gcp_flag_allowed firebase-messaging-sender-id || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_messaging_sender_id="${2-}"
        shift 2 || usage
        ;;
      --firebase-messaging-sender-id=*)
        gcp_flag_allowed firebase-messaging-sender-id || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_messaging_sender_id="${1#*=}"
        shift
        ;;
      --firebase-project-id)
        gcp_flag_allowed firebase-project-id || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_project_id="${2-}"
        shift 2 || usage
        ;;
      --firebase-project-id=*)
        gcp_flag_allowed firebase-project-id || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_project_id="${1#*=}"
        shift
        ;;
      --firebase-storage-bucket)
        gcp_flag_allowed firebase-storage-bucket || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_storage_bucket="${2-}"
        shift 2 || usage
        ;;
      --firebase-storage-bucket=*)
        gcp_flag_allowed firebase-storage-bucket || {
          echo "不明な引数: $1" >&2
          usage
        }
        firebase_storage_bucket="${1#*=}"
        shift
        ;;
      -h | --help) usage ;;
      *)
        echo "不明な引数: $1" >&2
        usage
        ;;
    esac
  done

  local name
  for name in ${GCP_REQUIRED}; do
    case "$name" in
      project) reject_gcp_value "project" "$project" ;;
      billing-account) reject_gcp_value "billing-account" "$billing_account" ;;
      image) reject_gcp_value "image" "$image" ;;
      state-bucket) reject_gcp_value "state-bucket" "$state_bucket" ;;
      region) reject_gcp_value "region" "$region" ;;
      firebase-api-key) reject_gcp_value "firebase-api-key" "$firebase_api_key" ;;
      firebase-auth-domain) reject_gcp_value "firebase-auth-domain" "$firebase_auth_domain" ;;
      firebase-app-id) reject_gcp_value "firebase-app-id" "$firebase_app_id" ;;
      firebase-messaging-sender-id) reject_gcp_value "firebase-messaging-sender-id" "$firebase_messaging_sender_id" ;;
      firebase-project-id) reject_gcp_value "firebase-project-id" "$firebase_project_id" ;;
      firebase-storage-bucket)
        if [[ -n "$firebase_storage_bucket" ]]; then
          reject_gcp_value "firebase-storage-bucket" "$firebase_storage_bucket"
        fi
        ;;
      *)
        echo "未知の必須引数: ${name}" >&2
        exit 2
        ;;
    esac
  done

  if [[ -n "$state_bucket" && "$state_bucket" == */* ]]; then
    echo "state-bucket はバケット名だけです。gs:// や / は付けません。" >&2
    exit 2
  fi
}

export_gcp_project() {
  export GOOGLE_PROJECT="$project"
  export GOOGLE_CLOUD_PROJECT="$project"
  export CLOUDSDK_CORE_PROJECT="$project"
  export GOOGLE_BILLING_PROJECT="$project"
  # 変数の既定を使う。環境に残った TF_VAR でプロジェクトやサイトを変えない。
  unset TF_VAR_project_id TF_VAR_region TF_VAR_billing_account TF_VAR_container_image TF_VAR_hosting_site_id
}
