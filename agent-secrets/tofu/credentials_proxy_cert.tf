# Certificate material for the credentials-proxy <-> omp-sandbox TLS endpoint.
#
# omp sandboxes resolve openrouter.ai to the envoy container, which terminates
# TLS with the server cert below. The CA cert is baked into the sandbox image
# (system trust store + NODE_EXTRA_CA_CERTS for Bun).
#
# Private keys live only here in state and in infisical. Hosts fetch what they
# need on demand via credentials-proxy/materialize-certs.sh; nothing is
# committed to git. Rotating: change something (or wait for early renewal on
# the server cert), apply, restart the proxy, rebuild the sandbox image.

resource "tls_private_key" "credentials_proxy_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "credentials_proxy_ca" {
  private_key_pem   = tls_private_key.credentials_proxy_ca.private_key_pem
  is_ca_certificate = true

  subject {
    common_name = "omp-sandbox local CA"
  }

  validity_period_hours = 24 * 365 * 10 # 10 years

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

resource "tls_private_key" "credentials_proxy_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "credentials_proxy_server" {
  private_key_pem = tls_private_key.credentials_proxy_server.private_key_pem
  dns_names       = ["openrouter.ai"]

  subject {
    common_name = "openrouter.ai"
  }
}

resource "tls_locally_signed_cert" "credentials_proxy_server" {
  cert_request_pem   = tls_cert_request.credentials_proxy_server.cert_request_pem
  ca_private_key_pem = tls_private_key.credentials_proxy_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.credentials_proxy_ca.cert_pem

  validity_period_hours = 24 * 365 # 1 year
  early_renewal_hours   = 24 * 30  # re-sign a month early on the next apply

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

locals {
  credentials_proxy_cert_secrets = {
    CREDENTIALS_PROXY_CA_CERT     = tls_self_signed_cert.credentials_proxy_ca.cert_pem
    CREDENTIALS_PROXY_CA_KEY      = tls_private_key.credentials_proxy_ca.private_key_pem
    CREDENTIALS_PROXY_SERVER_CERT = tls_locally_signed_cert.credentials_proxy_server.cert_pem
    CREDENTIALS_PROXY_SERVER_KEY  = tls_private_key.credentials_proxy_server.private_key_pem
  }
}

# Local CLI link for this monorepo: lets `infisical run` / `infisical secrets`
# work with zero --projectId/--env flags. Gitignored; regenerated on apply.
# Generated into the monorepo root (two levels up from this module).
resource "local_sensitive_file" "infisical_project_config" {
  filename        = "${path.module}/../../.infisical.json"
  file_permission = "0600"
  content = jsonencode({
    workspaceId        = infisical_project.agent.id
    defaultEnvironment = infisical_project_environment.global.slug
  })
}

resource "infisical_secret" "credentials_proxy_cert" {
  for_each = local.credentials_proxy_cert_secrets

  name         = each.key
  value        = each.value
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
}
