resource "infisical_secret" "github_classic_pat" {
  name             = "GITHUB_TOKEN"
  value_wo         = "paste github token here"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.agent.id
  folder_path      = "/"
}
