resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  delete_protection_state = "DELETE_PROTECTION_ENABLED"
  deletion_policy         = "ABANDON"

  depends_on = [google_project_service.api]
}

resource "google_firebaserules_ruleset" "firestore" {
  project = var.project_id

  source {
    files {
      name    = "firestore.rules"
      content = file("${path.module}/../firebase/firestore.rules")
    }
  }

  depends_on = [google_project_service.api]
}

resource "google_firebaserules_release" "firestore" {
  project = var.project_id
  name    = "cloud.firestore"
  # name は projects/{project}/rulesets/{id} のままである。前に同じ形を足さない。
  ruleset_name = google_firebaserules_ruleset.firestore.name

  depends_on = [google_firestore_database.default]
}

resource "google_firebase_web_app" "web" {
  provider     = google-beta
  project      = var.project_id
  display_name = "kazokuai"

  depends_on = [google_project_service.api]
}

data "google_firebase_web_app_config" "web" {
  provider   = google-beta
  project    = var.project_id
  web_app_id = google_firebase_web_app.web.app_id
}

# メールアドレスとパスワードのログインは、ここで有効にしない。
# google_identity_platform_config は署名の鍵を状態に書く。
# 有効にする手順は infra/README.md にある。

# 既定のサイト。サイト ID はプロジェクト ID で、状態へ取り込み済みである。
# アドレス google_firebase_hosting_site.web は変えない。変えると、取り込み済みのサイトを消そうとする。
resource "google_firebase_hosting_site" "web" {
  provider = google-beta
  project  = var.project_id
  site_id  = var.project_id
  app_id   = google_firebase_web_app.web.app_id

  # 既定の DELETE だと、replace のときにサイトを消す。PREVENT は ForceNew ではない。
  deletion_policy = "PREVENT"

  depends_on = [google_project_service.api]
}

# Web 版を公開するサイト。既定のサイトは残し、ここへ出す。
# Web アプリは既定のサイトにつながっていて、1 つのアプリは 1 つのサイトにしかつなげないので、
# このサイトには app_id を付けない。アプリは Firebase の設定をビルドのときに受け取るので、要らない。
resource "google_firebase_hosting_site" "published" {
  provider = google-beta
  project  = var.project_id
  site_id  = var.hosting_site_id

  # 既定の DELETE だと、replace のときにサイトを消す。PREVENT は ForceNew ではない。
  deletion_policy = "PREVENT"

  depends_on = [google_project_service.api]
}
