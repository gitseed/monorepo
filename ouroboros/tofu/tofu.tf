terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.56.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.22.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.6.0"
    }
    infisical = {
      version = "0.19.6"
      source  = "infisical/infisical"
    }
    restapi = {
      source = "mastercard/restapi"
      # Version 3 was rewritten with AI and it sucks.
      # Both version 2 and 3 are abandonware.
      version = "2.0.1"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.0"
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


provider "aws" {
  region = local.workspace.aws_region
}

provider "cloudflare" {
  api_token = data.infisical_secrets.ouroboros.secrets.CLOUDFLARE_API_TOKEN.value
}

provider "http" {}

provider "infisical" {
  auth = {
    aws_iam = {
    }
  }
}

provider "restapi" {
  alias = "infisical_project_memberships"
  uri   = "https://us.infisical.com/api/v1"
  headers = {
    Authorization  = "Bearer ${infisical_identity_token_auth_token.human_inviter.token}"
    "Content-Type" = "application/json"
  }
}

provider "time" {}
