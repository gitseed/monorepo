# This is the project where we keep the human admin credentials.
resource "infisical_project" "agent" {
  name                       = "agent"
  slug                       = "agent"
  type                       = "secret-manager"
  should_create_default_envs = false
}

# Just one environment for admin creds for now, since I just have one laptop...
resource "infisical_project_environment" "global" {
  name       = tofu.workspace
  project_id = infisical_project.agent.id
  slug       = tofu.workspace
}

resource "infisical_project_user" "human_admin" {
  project_id = infisical_project.agent.id
  username   = data.infisical_secrets.ouroboros.secrets.EMAIL_ADDRESS.value
  roles = [{
    role_slug = "admin"
  }]
}
