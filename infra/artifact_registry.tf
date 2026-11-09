resource "google_artifact_registry_repository" "backend" {
  project       = var.project_id
  location      = var.region
  repository_id = local.service_name
  description   = "バックエンドのコンテナ"
  format        = "DOCKER"

  depends_on = [google_project_service.api]
}
