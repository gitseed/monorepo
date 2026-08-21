resource "infisical_secret" "twilio_api_key" {
  name             = "TWILIO_API_KEY"
  value_wo         = "paste twilio read-only api key here"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}

resource "infisical_secret" "twilio_api_secret" {
  name             = "TWILIO_API_SECRET"
  value_wo         = "paste twilio read-only api secret here"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
