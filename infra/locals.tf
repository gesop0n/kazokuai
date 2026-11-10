locals {
  # provider 8.10.0 は URL を billingAccounts/{{billing_account}}/budgets と組む。
  # 接頭辞を残すと billingAccounts/billingAccounts/... になり、予算を作れない。
  billing_account = trimprefix(var.billing_account, "billingAccounts/")

  # Cloud Run のサービス名。Hosting の /api/** は、公開のときにこの名前へ回す。
  service_name = "kazokuai"

  # 値は人が gcloud で入れる。ここにあるのは Secret Manager 上の名前だけ。
  gemini_secret_id = "gemini-api-key"
  phone_secret_id  = "phone-shared-secret"

  # 予約のタスクが呼ぶ、バックエンド自身の URL。Cloud Run の決定的な URL である。
  # サービス資源の uri は参照しない。参照すると、このサービスが自分に頼る。
  backend_url = "https://${local.service_name}-${data.google_project.this.number}.${var.region}.run.app"

  services = toset([
    "artifactregistry.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudtasks.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "firebaserules.googleapis.com",
    "firestore.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "identitytoolkit.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "securetoken.googleapis.com",
    "sts.googleapis.com",
  ])
}
