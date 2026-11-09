resource "google_service_account" "backend" {
  project      = var.project_id
  account_id   = "${local.service_name}-backend"
  display_name = "kazokuai のバックエンド"

  depends_on = [google_project_service.api]
}

resource "google_project_iam_member" "backend_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_secret_manager_secret_iam_member" "backend_gemini" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.gemini_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

resource "google_secret_manager_secret_iam_member" "backend_phone" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.phone_shared_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.backend.email}"
}

# イメージを引くのは、実行時のサービスアカウントではなく Cloud Run のサービスエージェント。
resource "google_project_service_identity" "run" {
  provider = google-beta
  project  = var.project_id
  service  = "run.googleapis.com"

  depends_on = [google_project_service.api]
}

resource "google_artifact_registry_repository_iam_member" "run_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.backend.location
  repository = google_artifact_registry_repository.backend.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_project_service_identity.run.email}"
}
