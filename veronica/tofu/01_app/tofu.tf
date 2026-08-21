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

    # Renders app/wrangler.jsonc from its template (see wrangler.tf).
    local = {
      source  = "hashicorp/local"
      version = "2.9.0"
    }

    # The driver image is built by Cloud Build into Artifact Registry
    # (see image.tf) — no local Docker anywhere — and Cloudflare pulls it
    # from there. Google Cloud is also where future non-telephony pieces
    # will live.
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
    profile              = "cloudflare"
    bucket               = "tofu"
    workspace_key_prefix = "veronica"

    # The pre-split root's state object, adopted as-is: 01_app's resources
    # keep the exact state they always had (see ../README.md, "Migrating").
    key = "tofu"

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

# Reads CLOUDFLARE_API_TOKEN from the environment.
provider "cloudflare" {}

# Reads TWILIO_API_KEY/TWILIO_API_SECRET from the environment, falling back
# to TWILIO_ACCOUNT_SID/TWILIO_AUTH_TOKEN.
provider "twilio" {}

provider "google" {
  project = local.workspace.project_id
  region  = local.workspace.region
}
