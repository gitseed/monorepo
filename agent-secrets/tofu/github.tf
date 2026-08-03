resource "infisical_secret" "github_classic_pat" {
  name             = "GITHUB_TOKEN"
  value_wo         = "paste github token here"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}

# github.com's git smart-HTTP takes a base64 of a classic pat
resource "infisical_secret" "github_classic_pat_basic" {
  name         = "GITHUB_TOKEN_BASIC"
  value        = base64encode("x-access-token:${data.infisical_secrets.agent.secrets.GITHUB_TOKEN.value}")
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
}
