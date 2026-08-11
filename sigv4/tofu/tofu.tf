terraform {
  required_version = "1.12.5"
  required_providers {
    github = {
      source  = "integrations/github"
      version = "6.12.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.56.0"
    }
  }
  backend "s3" {
    profile                     = "cloudflare"
    bucket                      = "tofu"
    workspace_key_prefix        = "sigv4"
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
  region = "us-east-1"
}
