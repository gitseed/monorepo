resource "infisical_secret" "twilio_api_key" {
  name             = "TWILIO_API_KEY"
  value_wo         = "notset"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}

resource "infisical_secret" "twilio_api_secret" {
  name             = "TWILIO_API_SECRET"
  value_wo         = "notset"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}
