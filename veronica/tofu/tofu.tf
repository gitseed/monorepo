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

    # Calls the undocumented Cloudflare Containers registries API from the
    # apply itself, using a scoped API token created alongside it — no
    # manual wrangler command, no key on disk.
    restapi = {
      source  = "mastercard/restapi"
      version = "2.0.1"
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

# Reads CLOUDFLARE_API_TOKEN from the environment.
provider "cloudflare" {}

# Reads TWILIO_API_KEY/TWILIO_API_SECRET from the environment, falling back
# to TWILIO_ACCOUNT_SID/TWILIO_AUTH_TOKEN.
provider "twilio" {}

provider "google" {
  project = local.workspace.project_id
  region  = local.workspace.region
}

# The permission-group catalog for account-scoped tokens; pick "Workers
# Containers Write" by exact name rather than hardcoding an id.
data "cloudflare_api_token_permission_groups_list" "account_scope" {
  scope = "com.cloudflare.api.account"

  lifecycle {
    postcondition {
      condition     = contains([for group in self.result : group.name], "Workers Containers Write")
      error_message = "The permission-group catalog has no 'Workers Containers Write'; the registries token cannot be scoped."
    }
  }
}

locals {
  containers_write_id = one([
    for group in data.cloudflare_api_token_permission_groups_list.account_scope.result :
    group.id if group.name == "Workers Containers Write"
  ])
}

# A token that can do exactly one thing on exactly one account: manage
# container registries. Its value lives in state, which is acceptable for
# a scope this narrow.
resource "cloudflare_account_token" "registry" {
  account_id = local.workspace.cloudflare_account_id
  name       = "${tofu.workspace}-container-registries"

  policies = [{
    effect = "allow"
    permission_groups = [
      { id = local.containers_write_id }
    ]
    resources = jsonencode({
      "com.cloudflare.api.account.${local.workspace.cloudflare_account_id}" = "*"
    })
  }]
}

# Speaks the undocumented Containers registries API (see registries.tf).
# The scoped token above exists only at apply time; OpenTofu defers
# configuring the provider until the value is known, and destroys the
# registry object before the token. Pinned to the SDKv2 line (2.x) in
# required_providers: 3.0.0's framework rewrite rejects unknown
# provider-config values at plan, which breaks exactly this bootstrap.
provider "restapi" {
  alias = "cloudflare_containers"
  uri   = "https://api.cloudflare.com/client/v4/accounts/${local.workspace.cloudflare_account_id}/containers"

  headers = {
    Authorization = "Bearer ${cloudflare_account_token.registry.value}"
  }
}
