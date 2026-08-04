resource "infisical_secret" "firecrawl_api_key" {
  name             = "FIRECRAWL_API_KEY"
  value_wo         = "paste firecrawl key here"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
