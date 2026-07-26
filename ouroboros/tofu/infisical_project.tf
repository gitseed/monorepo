resource "infisical_project" "ouroboros" {
  name                       = "ouroboros"
  slug                       = "ouroboros"
  type                       = "secret-manager"
  should_create_default_envs = false
}

# Just one environment for admin creds for now, since I just have one laptop...
resource "infisical_project_environment" "global" {
  name       = "global"
  project_id = infisical_project.homouroboroselab.id
  slug       = "global"
}

resource "infisical_project_identity" "user_lister" {
  project_id  = infisical_project.homelab.id
  identity_id = infisical_identity.user_lister.id
  roles       = [{ role_slug = "admin" }]
}
