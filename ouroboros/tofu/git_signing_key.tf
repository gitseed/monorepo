resource "tls_private_key" "git_signing" {
  algorithm = "ED25519"
}

resource "infisical_secret" "git_signing_key" {
  name         = "GIT_SIGNING_KEY"
  value        = tls_private_key.git_signing.private_key_openssh
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.ouroboros.id
  folder_path  = "/"
}

# The GitHub Terraform provider has no ssh_signing_key resource,
# so use the REST API directly via Mastercard/restapi.
locals {
  signing_key_data = jsonencode({
    title = "ouroboros signing key"
    key   = tls_private_key.git_signing.public_key_openssh
  })
}

resource "restapi_object" "github_ssh_signing_key" {
  path                      = "/user/ssh_signing_keys"
  data                      = local.signing_key_data
  ignore_all_server_changes = true
  force_new                 = [local.signing_key_data]
}
