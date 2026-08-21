terraform {
  required_version = "1.12.3"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.22.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "7.39.0"
    }
    restapi = {
      source  = "mastercard/restapi"
      version = "2.0.1"
    }
  }
  backend "s3" {
    profile                     = "cloudflare"
    bucket                      = "tofu-sensitive"
    workspace_key_prefix        = "veronica"
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

provider "cloudflare" {}

provider "google" {
  project = local.workspace.project_id
  region  = local.workspace.region
}

# Calls the undocumented Cloudflare Containers registries API.
provider "restapi" {
  alias = "cloudflare_containers"
  uri   = "https://api.cloudflare.com/client/v4/accounts/${local.workspace.cloudflare_account_id}/containers"
  headers = {
    Authorization = "Bearer ${cloudflare_account_token.registry.value}"
  }
}
