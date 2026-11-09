# 秘密の入れ物だけを作る。google_secret_manager_secret_version は作らない。
# バージョンの中身は状態に残るので、値は人が gcloud で入れる。

resource "google_secret_manager_secret" "gemini_api_key" {
  project   = var.project_id
  secret_id = local.gemini_secret_id

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  # 人が入れたバージョンごと消えないようにする。消すときは、ここを false にしてから destroy する。
  deletion_protection = true

  depends_on = [google_project_service.api]
}

resource "google_secret_manager_secret" "phone_shared_secret" {
  project   = var.project_id
  secret_id = local.phone_secret_id

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  deletion_protection = true

  depends_on = [google_project_service.api]
}
