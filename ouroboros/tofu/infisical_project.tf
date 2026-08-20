# This is the project where we keep the human admin credentials.
resource "infisical_project" "ouroboros" {
  name                       = "ouroboros"
  slug                       = "ouroboros"
  type                       = "secret-manager"
  should_create_default_envs = false
}

resource "infisical_project_environment" "global" {
  name       = "global"
  project_id = infisical_project.ouroboros.id
  slug       = "global"
}

resource "infisical_project_user" "human_admin" {
  project_id = infisical_project.ouroboros.id
  username   = data.infisical_secrets.ouroboros.secrets.EMAIL_ADDRESS.value
  roles = [{
    role_slug = "admin"
  }]
}
