# Bridge the read-only AWS credentials from the ouroboros project
# into the agent project, where up.bash loads them via `infisical run`.
resource "infisical_secret" "aws_access_key_id" {
  name         = "AWS_ACCESS_KEY_ID"
  value        = data.infisical_secrets.ouroboros.secrets.AWS_ACCESS_KEY_ID.value
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
}

resource "infisical_secret" "aws_secret_access_key" {
  name         = "AWS_SECRET_ACCESS_KEY"
  value        = data.infisical_secrets.ouroboros.secrets.AWS_SECRET_ACCESS_KEY.value
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
}
