data "infisical_identity_details" "self" {
}

locals {
  org_id = data.infisical_identity_details.self.organization.id
}

data "infisical_secrets" "ouroboros" {
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.ouroboros.id
  folder_path  = "/"
}
