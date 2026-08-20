# Cloudflare pulls the driver image from Artifact Registry, and this file
# hands it the credential end-to-end: a key for the read-only pull SA,
# stored as a containers-scoped Secrets Store secret, registered through
# the (undocumented) Containers registries API — the same three moves
# `wrangler containers registries configure` makes, minus the human piping
# a key file around. The API call itself is made by the restapi provider
# using a single-purpose account token minted right here, so the main
# token's breadth never reaches the undocumented surface.
#
# The API, from wrangler's own client (there are no docs to cite):
#   GET    /accounts/{account}/containers/registries
#   POST   /accounts/{account}/containers/registries
#            {domain, is_public, auth: {public_credential,
#             private_credential: {store_id, secret_name}}, kind: "GAR"}
#   DELETE /accounts/{account}/containers/registries/{domain}

locals {
  registry_hostname = split("/", local.image_repository)[0]
}

# The private half of the pull identity (image.tf owns the SA itself).
# google_service_account_key.private_key is the base64 of the JSON key
# file — exactly the encoding wrangler stores, so it passes through
# untouched.
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
