resource "google_cloud_run_v2_service" "backend" {
  project  = var.project_id
  name     = local.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # 既定は true。外す 1 回は infra/run.sh apply --allow-replace を使う。
  deletion_protection = var.deletion_protection

  # プロバイダーの deletion_policy。ForceNew ではないので、状態の値をその場で変える。
  # PREVENT が状態に入ったあと、apply がこのサービスを消そうとすると失敗する。
  deletion_policy = "PREVENT"

  # gcloud run deploy が載せるイメージと、そのクライアント名を戻さない。
  # タグは付けない。タグを付けると、次の plan がリビジョンの差分を出す。
  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].containers[0].image,
    ]
  }

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

      # 予約のタスク。URL は local.backend_url で、このサービスの uri は参照しない。
      env {
        name  = "BOOKING_TASK_QUEUE"
        value = google_cloud_tasks_queue.bookings.id
      }

      env {
        name  = "BOOKING_TASK_ACCOUNT"
        value = google_service_account.tasks.email
      }

      env {
        name  = "BOOKING_TASK_AUDIENCE"
        value = local.backend_url
      }
    }
  }

  depends_on = [
    google_project_service.api,
    google_project_iam_member.backend_firestore,
    google_secret_manager_secret_iam_member.backend_gemini,
    google_secret_manager_secret_iam_member.backend_phone,
    google_artifact_registry_repository_iam_member.run_reader,
    google_cloud_tasks_queue_iam_member.backend_enqueuer,
    google_service_account_iam_member.backend_tasks,
    google_service_account_iam_member.cloudtasks_token,
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
