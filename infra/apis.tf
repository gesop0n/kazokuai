resource "google_project_service" "api" {
  for_each = local.services

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}
