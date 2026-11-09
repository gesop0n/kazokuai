locals {
  # provider 8.10.0 は URL を billingAccounts/{{billing_account}}/budgets と組む。
  # 接頭辞を残すと billingAccounts/billingAccounts/... になり、予算を作れない。
  billing_account = trimprefix(var.billing_account, "billingAccounts/")

  # Cloud Run のサービス名。Hosting の /api/** は、公開のときにこの名前へ回す。
  service_name = "kazokuai"

  # 値は人が gcloud で入れる。ここにあるのは Secret Manager 上の名前だけ。
  gemini_secret_id = "gemini-api-key"
  phone_secret_id  = "phone-shared-secret"

  services = toset([
    "artifactregistry.googleapis.com",
    "billingbudgets.googleapis.com",
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
