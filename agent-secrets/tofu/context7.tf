resource "infisical_secret" "context7_api_key" {
  name             = "CONTEXT7_API_KEY"
  value_wo         = "paste context7 key here"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
