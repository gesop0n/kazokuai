resource "google_cloud_run_v2_service" "backend" {
  project  = var.project_id
  name     = local.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # 既定が true。消すときは、ここを false にしてから destroy する。
  deletion_protection = true

  # サービス全体の上限。改訂を切り替えているあいだも、インスタンスは 1 つを超えない。
  scaling {
    min_instance_count = 0
    max_instance_count = 1
  }

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    timeout         = "3600s"
    service_account = google_service_account.backend.email

    containers {
      image = var.container_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        # false は、インスタンスが生きているあいだ CPU を割り当て続ける。
        # true だと、応答を返したあとのまとめが止まる。
        cpu_idle = false
      }

      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }

      env {
        name = "GEMINI_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.gemini_api_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        # プロセスは PHONE_SECRET を読む。Secret Manager の名前は phone-shared-secret のまま。
        name = "PHONE_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.phone_shared_secret.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.api,
    google_project_iam_member.backend_firestore,
    google_secret_manager_secret_iam_member.backend_gemini,
    google_secret_manager_secret_iam_member.backend_phone,
    google_artifact_registry_repository_iam_member.run_reader,
  ]
}

# Hosting の /api/** と、電話機からの直接の接続は、Google の IAM では公開する。
# 家族の API は Firebase の ID トークンで、電話機の API は合言葉でバックエンドが断る。
resource "google_cloud_run_v2_service_iam_member" "public" {
  project  = google_cloud_run_v2_service.backend.project
  location = google_cloud_run_v2_service.backend.location
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
