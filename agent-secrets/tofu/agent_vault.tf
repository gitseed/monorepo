data "infisical_identity_details" "self" {
}

locals {
  org_id = data.infisical_identity_details.self.organization.id
}

# This identity has no organization-wide access. Its only permission is the
# viewer role on the agent project below.
resource "infisical_identity" "agent_sandbox_vault" {
  name   = "agent-sandbox-vault"
  role   = "no-access"
  org_id = local.org_id
}

resource "infisical_identity_universal_auth" "agent_sandbox_vault" {
  identity_id                 = infisical_identity.agent_sandbox_vault.id
  access_token_ttl            = 3600
  access_token_max_ttl        = 3600
  access_token_num_uses_limit = 0

  # The laptop can move between networks, so the identity is constrained by
  # project role rather than source IP.
  client_secret_trusted_ips = [
    {
      ip_address = "0.0.0.0/0"
    },
    {
      ip_address = "::/0"
    },
  ]

  access_token_trusted_ips = [
    {
      ip_address = "0.0.0.0/0"
    },
    {
      ip_address = "::/0"
    },
  ]
}

resource "infisical_identity_universal_auth_client_secret" "agent_sandbox_vault" {
  identity_id = infisical_identity.agent_sandbox_vault.id
  description = "Ephemeral agent-sandbox Agent Vault container"

  depends_on = [infisical_identity_universal_auth.agent_sandbox_vault]
}

resource "infisical_project_identity" "agent_sandbox_vault" {
  project_id  = infisical_project.agent.id
  identity_id = infisical_identity.agent_sandbox_vault.id

  roles = [
    {
      role_slug = "viewer"
    },
  ]
}

output "agent_vault_project_id" {
  value = infisical_project.agent.id
}

output "agent_vault_client_id" {
  value = infisical_identity_universal_auth_client_secret.agent_sandbox_vault.client_id
}

output "agent_vault_client_secret" {
  sensitive = true
  value     = infisical_identity_universal_auth_client_secret.agent_sandbox_vault.client_secret
}
