# Cloudflare pulls the driver image from Artifact Registry, and this file
# hands it the credential end-to-end: a key for the read-only pull SA,
# stored as a containers-scoped Secrets Store secret, registered through
# the (undocumented) Containers registries API — the same three moves
# `wrangler containers registries configure` makes, minus the human piping
# a key file around. The API call itself is made by the restapi provider
# using a single-purpose account token minted right here, so the main
# token's breadth never reaches the undocumented surface.
#
# Everything here lands in this layer's state with secrets in it (the SA
# key, the token value), which is why it is the sensitive layer.
#
# The API, from wrangler's own client (there are no docs to cite):
#   GET    /accounts/{account}/containers/registries
#   POST   /accounts/{account}/containers/registries
#            {domain, is_public, auth: {public_credential,
#             private_credential: {store_id, secret_name}}, kind: "GAR"}
#   DELETE /accounts/{account}/containers/registries/{domain}
#
# There is no per-object GET, which breaks `tofu import` (the importer
# can only read GET {path}/{id}); to re-adopt an existing record into
# state, run repair-gar-registry.sh instead.

locals {
  # Mirrors 01_app/image.tf's repository layout; the repository itself
  # lives there, and the layers are wired only by these stable names.
  image_repository = "${local.workspace.region}-docker.pkg.dev/${local.workspace.project_id}/${tofu.workspace}/driver"

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

# Cloudflare's identity for pulling the image: the SA email is the public
# half (01_app grants it reader on the repository by name), and the key
# below is the private half. It lives in this layer because its key does.
resource "google_service_account" "image_pull" {
  account_id   = "voice-pull-${tofu.workspace}"
  display_name = "Veronica driver image pull (Cloudflare)"
  depends_on   = [google_project_service.services]
}

# The private half of the pull identity. google_service_account_key's
# private_key is the base64 of the JSON key file — exactly the encoding
# wrangler stores, so it passes through untouched.
resource "google_service_account_key" "image_pull" {
  service_account_id = google_service_account.image_pull.name
}

# Wrangler's flow demands exactly one Secrets Store and uses it; mirror
# that, including refusing to guess between several.
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
# container registries.
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
  provider = restapi.cloudflare_containers

  path      = "/registries"
  object_id = local.registry_hostname

  # Registry records have no "id" — the domain is their identity. Without
  # this, the provider's post-create read finds the record but can't
  # extract an id from it and declares the object absent.
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

  # Reads list the collection and pick our domain out of the v4 envelope.
  read_path = "/registries"
  read_search = {
    results_key  = "result"
    search_key   = "domain"
    search_value = local.registry_hostname
  }

  destroy_path = "/registries/{id}"

  # The list response echoes nothing sensitive back (no auth block), so
  # drift against our data is structural, not real; and the API has no
  # update verb anyway — any input change must recreate instead.
  ignore_all_server_changes = true
  force_new = [
    local.registry_hostname,
    google_service_account.image_pull.email,
    cloudflare_secrets_store_secret.gar_key.store_id,
    cloudflare_secrets_store_secret.gar_key.name,
  ]
}
