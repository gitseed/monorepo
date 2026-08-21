resource "google_project_service" "iam" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "agent_readonly" {
  account_id   = "agent-readonly"
  display_name = "Agent read-only"
  depends_on   = [google_project_service.iam]
}

resource "google_project_iam_member" "agent_readonly_viewer" {
  project = local.workspace.google_project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.agent_readonly.email}"
}

resource "google_service_account_key" "agent_readonly" {
  service_account_id = google_service_account.agent_readonly.name
}

resource "infisical_secret" "google_service_account_key" {
  name             = "GOOGLE_SERVICE_ACCOUNT_KEY"
  value_wo         = google_service_account_key.agent_readonly.private_key
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
