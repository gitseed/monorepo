locals {
  image_repository  = "${local.workspace.region}-docker.pkg.dev/${local.workspace.project_id}/${tofu.workspace}/driver"
  registry_hostname = split("/", local.image_repository)[0]
}

resource "google_project_service" "services" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
  lifecycle {
    destroy = false
  }
}

resource "google_service_account" "image_pull" {
  account_id   = "voice-pull-${tofu.workspace}"
  display_name = "Veronica driver image pull (Cloudflare)"
  depends_on   = [google_project_service.services]
}

resource "google_service_account_key" "image_pull" {
  service_account_id = google_service_account.image_pull.name
}

data "cloudflare_secrets_stores" "all" {
  account_id = local.workspace.cloudflare_account_id
  lifecycle {
    postcondition {
      condition     = length(self.result) == 1
      error_message = "Expected exactly one Secrets Store on the account (found ${length(self.result)}); the registry credential does not know where to live."
    }
  }
}

resource "cloudflare_secrets_store_secret" "gar_key" {
  account_id = local.workspace.cloudflare_account_id
  store_id   = data.cloudflare_secrets_stores.all.result[0].id
  name       = "${tofu.workspace}-gar-pull"
  scopes     = ["containers"]
  value      = google_service_account_key.image_pull.private_key
  comment    = "Created by OpenTofu: credentials for image registry ${local.registry_hostname}"
}

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

resource "restapi_object" "gar_registry" {
  provider     = restapi.cloudflare_containers
  path         = "/registries"
  object_id    = local.registry_hostname
  id_attribute = "domain"
  data = jsonencode({
    domain    = local.registry_hostname
    is_public = false
    kind      = "GAR"
    auth = {
      public_credential = google_service_account.image_pull.email
      private_credential = {
        store_id    = cloudflare_secrets_store_secret.gar_key.store_id
        secret_name = cloudflare_secrets_store_secret.gar_key.name
      }
    }
  })
  read_path = "/registries"
  read_search = {
    results_key  = "result"
    search_key   = "domain"
    search_value = local.registry_hostname
  }
  destroy_path              = "/registries/{id}"
  ignore_all_server_changes = true
  force_new = [
    local.registry_hostname,
    google_service_account.image_pull.email,
    cloudflare_secrets_store_secret.gar_key.store_id,
    cloudflare_secrets_store_secret.gar_key.name,
  ]
}
