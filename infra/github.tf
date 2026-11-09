# GitHub Actions の main だけが、鍵なしでデプロイ用のサービスアカウントになる。
# このリポジトリは 2026-11-05 に作られ、OIDC の subject は immutable である。
# 接頭辞は repo:gesop0n@133982741/kazokuai@1446577671。
# 環境を使わない main の workflow_dispatch では、そのあとに :ref:refs/heads/main が付く。
# プロバイダーの条件は、リポジトリ名と ref でもう一度断る。

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "gesop0n/kazokuai の main からデプロイする"

  depends_on = [google_project_service.api]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub"
  description                        = "gesop0n/kazokuai の refs/heads/main だけを受け付ける"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = join(" && ", [
    "assertion.repository == 'gesop0n/kazokuai'",
    "assertion.ref == 'refs/heads/main'",
    "assertion.ref_type == 'branch'",
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  depends_on = [google_project_service.api]
}

resource "google_service_account" "deploy" {
  project      = var.project_id
  account_id   = "${local.service_name}-deploy"
  display_name = "kazokuai のデプロイ"

  # 鍵のファイルは作らない。

  depends_on = [google_project_service.api]
}

# このリポジトリだけに push できる。ほかのリポジトリには付かない。
resource "google_artifact_registry_repository_iam_member" "deploy_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.backend.location
  repository = google_artifact_registry_repository.backend.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deploy.email}"
}

# このサービスへの新しいリビジョンだけ。サービスの削除はこのロールに無い。
resource "google_cloud_run_v2_service_iam_member" "deploy" {
  project  = google_cloud_run_v2_service.backend.project
  location = google_cloud_run_v2_service.backend.location
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.deploy.email}"
}

# 新しいリビジョンは、実行用のサービスアカウントとして動く。actAs だけを渡す。
# トークンを作る権限は渡さない。
resource "google_service_account_iam_member" "deploy_runtime" {
  service_account_id = google_service_account.backend.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deploy.email}"
}

# 定義済みのロールで Hosting に公開できるのはこれだけである。
# サイトの作成と削除も含む。roles/editor は付けない。
# このロールには Service Usage の権限が無い。
resource "google_project_iam_member" "deploy_hosting" {
  project = var.project_id
  role    = "roles/firebasehosting.admin"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Firebase CLI は Hosting の公開前に、Service Usage で API が有効かを見る。
# 403 は捕捉しない。見る権限と、課金プロジェクトを指定する use だけを渡す。
# API の有効化や無効化は渡さない。
resource "google_project_iam_custom_role" "deploy_service_usage" {
  project     = var.project_id
  role_id     = "kazokuaiDeployServiceUsage"
  title       = "kazokuai のデプロイが API の有効を見る"
  description = "Firebase CLI が Hosting の公開前に Service Usage を見る。API の有効化はできない。"
  permissions = [
    "serviceusage.services.get",
    "serviceusage.services.use",
  ]

  depends_on = [google_project_service.api]
}

resource "google_project_iam_member" "deploy_service_usage" {
  project = var.project_id
  role    = google_project_iam_custom_role.deploy_service_usage.name
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/repo:gesop0n@133982741/kazokuai@1446577671:ref:refs/heads/main"
}
