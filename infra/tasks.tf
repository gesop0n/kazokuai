# 予約の時刻にバックエンドを呼ぶキュー。やり直しは 1 分おき、最大 10 分。
# 最初の 1 回を含めて 11 回まで。間隔は広げない。
resource "google_cloud_tasks_queue" "bookings" {
  project  = var.project_id
  name     = "bookings"
  location = var.region

  retry_config {
    max_attempts       = 11
    max_retry_duration = "600s"
    min_backoff        = "60s"
    max_backoff        = "60s"
    max_doublings      = 0
  }

  depends_on = [google_project_service.api]
}

resource "google_service_account" "tasks" {
  project      = var.project_id
  account_id   = "${local.service_name}-tasks"
  display_name = "kazokuai の予約のタスク"

  depends_on = [google_project_service.api]
}

# バックエンドが、キューにタスクを足す。
resource "google_cloud_tasks_queue_iam_member" "backend_enqueuer" {
  project  = var.project_id
  location = google_cloud_tasks_queue.bookings.location
  name     = google_cloud_tasks_queue.bookings.name
  role     = "roles/cloudtasks.enqueuer"
  member   = "serviceAccount:${google_service_account.backend.email}"
}

# バックエンドが、OIDC トークンの署名で、タスクのアカウントとして動く。
resource "google_service_account_iam_member" "backend_tasks" {
  service_account_id = google_service_account.tasks.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.backend.email}"
}

# タスクを配るとき、Cloud Tasks 自身がトークンへ署名する。
resource "google_project_service_identity" "cloudtasks" {
  provider = google-beta
  project  = var.project_id
  service  = "cloudtasks.googleapis.com"

  depends_on = [google_project_service.api]
}

resource "google_service_account_iam_member" "cloudtasks_token" {
  service_account_id = google_service_account.tasks.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_project_service_identity.cloudtasks.email}"
}
