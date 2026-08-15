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
    local = {
      source  = "hashicorp/local"
      version = "2.9.0"
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

# Same profile-aware lookup that up.bash does.
ephemeral "local_command" "infisical_machine_identity_id" {
  command   = "aws"
  arguments = ["configure", "get", "infisical_machine_identity_id"]
}

provider "infisical" {
  auth = {
    aws_iam = {
      identity_id = trimspace(ephemeral.local_command.infisical_machine_identity_id.stdout)
    }
  }
}

provider "local" {}

provider "time" {}
