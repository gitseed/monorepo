resource "infisical_secret" "email" {
  name             = "EMAIL_ADDRESS"
  value_wo         = "fakeaddress@example.com"
  value_wo_version = 1
  env_slug         = infisical_project_environment.global.slug
  workspace_id     = infisical_project.ouroboros.id
  folder_path      = "/"
}
