resource "infisical_secret" "openrouter_management_key" {
  name             = "OPENROUTER_API_KEY"
  value_wo         = "notset"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}
