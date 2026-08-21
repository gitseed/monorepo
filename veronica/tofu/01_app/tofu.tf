terraform {
  required_version = "1.12.3"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.22.0"
    }
    twilio = {
      source  = "twilio/twilio"
      version = "0.18.46"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "7.39.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.0"
    }
  }
  backend "s3" {
    profile                     = "cloudflare"
    bucket                      = "tofu"
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

provider "twilio" {}

provider "google" {
  project = local.workspace.project_id
  region  = local.workspace.region
}
