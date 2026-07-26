terraform {
  required_providers {
    infisical = {
      version = "0.19.6"
      source  = "infisical/infisical"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.6.0"
    }
    restapi = {
      source  = "mastercard/restapi"
      # Version 3 was rewritten with AI and it sucks.
      # Both version 2 and 3 are abandonware.
      version = "2.0.1"
    }
  }
  backend "s3" {
    profile                     = "cloudflare"
    bucket                      = "tofu-sensitive"
    workspace_key_prefix        = "ouroboros"
    key                         = basename(abspath(path.module))
    use_lockfile                = true
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

provider "infisical" {
  auth = {
    aws_iam = {
    }
  }
}

provider "http" {
}

# The token is minted by this configuration, so the provider cannot be fully
# configured until apply. Keep this on the SDKv2 line, as in veronica.
provider "restapi" {
  alias = "infisical_project_memberships"
  uri   = "https://us.infisical.com/api/v1"

  headers = {
    Authorization  = "Bearer ${infisical_identity_token_auth_token.user_lister.token}"
    "Content-Type" = "application/json"
  }
}
