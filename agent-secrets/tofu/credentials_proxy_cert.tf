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

locals {
  upstreams = yamldecode(file("${path.module}/../../sandbox/container/upstreams.yml"))

  # AWS regions matching the list in sandbox/container/envoy.pkl
  aws_regions = [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "ap-south-1", "ap-south-2", "ap-northeast-1", "ap-northeast-2",
    "ap-northeast-3", "ap-southeast-1", "ap-southeast-2", "ap-southeast-3",
    "ap-southeast-4", "ap-southeast-5", "ap-east-1",
    "ca-central-1", "ca-west-1",
    "eu-central-1", "eu-central-2", "eu-west-1", "eu-west-2", "eu-west-3",
    "eu-north-1", "eu-south-1", "eu-south-2",
    "il-central-1",
    "me-south-1", "me-central-1",
    "af-south-1",
    "sa-east-1",
    "us-gov-east-1", "us-gov-west-1",
    "cn-north-1", "cn-northwest-1",
  ]

  # Wildcard SANs for AWS egress: 1 global + 34 regional
  aws_wildcard_sans = ["*.amazonaws.com"] + [
    for r in local.aws_regions : "*.${r}.amazonaws.com"
  ]

  # All hostnames for the cert: existing upstreams + AWS wildcards
  all_dns_names = [for u in local.upstreams : u.host] + local.aws_wildcard_sans
}

resource "tls_cert_request" "credentials_proxy_server" {
  private_key_pem = tls_private_key.credentials_proxy_server.private_key_pem
  dns_names       = local.all_dns_names
  subject {
    common_name = local.upstreams[0].host
  }
}

resource "tls_locally_signed_cert" "credentials_proxy_server" {
  cert_request_pem      = tls_cert_request.credentials_proxy_server.cert_request_pem
  ca_private_key_pem    = tls_private_key.credentials_proxy_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.credentials_proxy_ca.cert_pem
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

resource "infisical_secret" "credentials_proxy_cert" {
  for_each     = local.credentials_proxy_cert_secrets
  name         = each.key
  value        = each.value
  env_slug     = infisical_project_environment.global.slug
  workspace_id = infisical_project.agent.id
  folder_path  = "/"
}
