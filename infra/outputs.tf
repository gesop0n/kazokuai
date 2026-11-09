output "firebase_api_key" {
  description = "Firebase の Web アプリのクライアント API キー。アプリに埋め込む公開の設定で、Gemini の API キーではない。"
  value       = data.google_firebase_web_app_config.web.api_key
}

output "firebase_auth_domain" {
  description = "Firebase Auth のドメイン。"
  value       = data.google_firebase_web_app_config.web.auth_domain
}

output "firebase_project_id" {
  description = "Firebase のプロジェクト ID。"
  value       = var.project_id
}

output "firebase_app_id" {
  description = "Firebase の Web アプリの ID。"
  value       = google_firebase_web_app.web.app_id
}

output "firebase_messaging_sender_id" {
  description = "Firebase Cloud Messaging の送信者 ID。"
  value       = data.google_firebase_web_app_config.web.messaging_sender_id
}

output "firebase_storage_bucket" {
  description = "Firebase のストレージバケット。未設定なら空である。"
  value       = data.google_firebase_web_app_config.web.storage_bucket
}

output "hosting_url" {
  description = "Firebase Hosting の URL。"
  value       = "https://${google_firebase_hosting_site.web.site_id}.web.app"
}

output "cloud_run_service" {
  description = "Cloud Run のサービス名。Hosting の /api/** はここへ回す。"
  value       = google_cloud_run_v2_service.backend.name
}

output "cloud_run_region" {
  description = "Cloud Run のリージョン。"
  value       = google_cloud_run_v2_service.backend.location
}

output "cloud_run_uri" {
  description = "Cloud Run の URL。電話機はここに直接つなぐ。"
  value       = google_cloud_run_v2_service.backend.uri
}

output "artifact_registry" {
  description = "バックエンドのイメージを置く Artifact Registry のホストとリポジトリ。"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.backend.repository_id}"
}

output "gemini_api_key_secret" {
  description = "Gemini の API キーを入れる Secret Manager の名前。値は出力しない。"
  value       = google_secret_manager_secret.gemini_api_key.secret_id
}

output "phone_shared_secret" {
  description = "電話機の合言葉を入れる Secret Manager の名前。値は出力しない。"
  value       = google_secret_manager_secret.phone_shared_secret.secret_id
}
