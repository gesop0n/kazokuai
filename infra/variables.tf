variable "project_id" {
  type        = string
  description = "Google Cloud のプロジェクト ID。既定値は置かない。"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id は Google Cloud のプロジェクト ID の形にしてください。"
  }
}

variable "region" {
  type        = string
  description = "リージョン。ADR 0003 のとおり東京。"
  default     = "asia-northeast1"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[0-9]$", var.region))
    error_message = "region は asia-northeast1 のようなリージョン名にしてください。"
  }
}

variable "billing_account" {
  type        = string
  description = "請求先アカウントの ID。XXXXXX-XXXXXX-XXXXXX。billingAccounts/ が付いていてもよい。"

  validation {
    condition     = can(regex("^(billingAccounts/)?[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}-[0-9A-Fa-f]{6}$", var.billing_account))
    error_message = "billing_account は XXXXXX-XXXXXX-XXXXXX の形にしてください。"
  }
}

variable "container_image" {
  type        = string
  description = "Cloud Run に載せるバックエンドのコンテナのイメージ。URI だけで、秘密の値は含めない。"

  validation {
    condition     = length(var.container_image) > 0 && !can(regex("[[:space:]]", var.container_image))
    error_message = "container_image にイメージの URI を、空白なしで入れてください。"
  }
}

variable "hosting_site_id" {
  type        = string
  description = "Web 版を公開する Firebase Hosting のサイト ID。既定のサイト（プロジェクト ID）とは別である。"
  default     = "kazokuai"

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,28}[a-z0-9])?$", var.hosting_site_id)) && var.hosting_site_id != var.project_id
    error_message = "hosting_site_id は 30 文字以内のホスト名ラベルにし、プロジェクト ID とは別にしてください。"
  }
}

variable "deletion_protection" {
  type        = bool
  description = "Cloud Run を消さない。壊れたサービスを作り直す 1 回だけ false にする。"
  default     = true
}
