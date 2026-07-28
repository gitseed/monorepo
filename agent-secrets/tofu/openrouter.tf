resource "openrouter_api_key" "main" {
  name = "monorepo-agent"
}

resource "infisical_secret" "openrouter_api_secret" {
  name         = "OPENROUTER_API_KEY"
  value        = openrouter_api_key.main.key
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
}
