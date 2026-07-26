# This is the project where we keep the human admin credentials.
resource "infisical_project" "ouroboros" {
  name                       = "ouroboros"
  slug                       = "ouroboros"
  type                       = "secret-manager"
  should_create_default_envs = false
}

# Just one environment for admin creds for now, since I just have one laptop...
resource "infisical_project_environment" "global" {
  name       = "global"
  project_id = infisical_project.ouroboros.id
  slug       = "global"
}

# The human inviter needs to be an admin on the project so that it can invite the humans to it.
resource "infisical_project_identity" "human_inviter" {
  project_id  = infisical_project.ouroboros.id
  identity_id = infisical_identity.human_inviter.id
  roles       = [{ role_slug = "admin" }]
}
