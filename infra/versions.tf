terraform {
  required_version = "1.17.1"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.10.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "8.10.0"
    }
  }

  # バケット名は init の -backend-config で渡す。
  # バケットは人が 1 回作り、オブジェクトのバージョニングを付ける。
  backend "gcs" {}
}

# project を省くと、gcloud の既定のプロジェクトが使われる。変数以外から渡さない。
# 予算 API は、利用者の ADC だと billing_project と user_project_override が要る。
provider "google" {
  project = var.project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.project_id
}

provider "google-beta" {
  project = var.project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.project_id
}
