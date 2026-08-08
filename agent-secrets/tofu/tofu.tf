terraform {
  required_providers {
    infisical = {
      version = "0.19.6"
      source  = "infisical/infisical"
    }
    openrouter = {
      source  = "cloudopsworks/openrouter"
      version = "0.2.18"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.0"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = "2.0.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.22.0"
    }
  }
  backend "s3" {
    profile                     = "cloudflare"
    bucket                      = "tofu-sensitive"
    workspace_key_prefix        = "agent-secrets"
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

data "infisical_projects" "ouroboros" {
  slug = "ouroboros"
}

data "infisical_secrets" "ouroboros" {
  env_slug     = tofu.workspace
  workspace_id = data.infisical_projects.ouroboros.id
  folder_path  = "/"
}

provider "infisical" {
  auth = {
    aws_iam = {
    }
  }
}

provider "openrouter" {
  api_key = data.infisical_secrets.ouroboros.secrets.OPENROUTER_API_KEY.value
}

provider "cloudflare" {
  api_token = data.infisical_secrets.ouroboros.secrets.CLOUDFLARE_API_TOKEN.value
}

provider "restapi" {
  uri                  = "https://api.github.com"
  write_returns_object = true
  id_attribute         = "id"
  headers = {
    Authorization = "Bearer ${data.infisical_secrets.agent.secrets.GITHUB_TOKEN.value}"
    Accept        = "application/vnd.github+json"
  }
}
