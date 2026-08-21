#!/usr/bin/env bash
# One-off repair: reconstruct the restapi_object.gar_registry state entry
# from the live API record (the API is list-only, so `tofu import` can't).
# Safe to delete once `tofu plan` shows no changes for the resource.
set -euo pipefail
cd "$(dirname "$0")"

ACCOUNT_ID=287cae24e46a0aeed1dbc2942fc58dd7
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN must be set}"

reg=$(
  curl -fsS -H @<(printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN") \
    "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/containers/registries" \
  | jq -ce '.result[] | select(.kind == "GAR")'
)

backup="gar-registry-backup-$(date +%Y%m%d%H%M%S).tfstate"
tofu state pull > "$backup"
echo "state backed up to $backup"

jq --argjson reg "$reg" '
  # data must byte-match registries.tf jsonencode(): compact, keys sorted.
  ( {
      auth: {
        private_credential: {
          secret_name: $reg.private_credential.secret_name,
          store_id: $reg.private_credential.store_id
        },
        public_credential: $reg.public_key
      },
      domain: $reg.domain,
      is_public: false,
      kind: "GAR"
    } | tojson ) as $data
  | .serial += 1
  | .resources |= map(select((.type == "restapi_object" and .name == "gar_registry") | not))
  | .resources += [{
      mode: "managed",
      type: "restapi_object",
      name: "gar_registry",
      provider: "provider[\"registry.opentofu.org/mastercard/restapi\"].cloudflare_containers",
      instances: [{
        schema_version: 0,
        attributes: {
          id: $reg.domain,
          path: "/registries",
          create_path: "",
          read_path: "/registries",
          update_path: "",
          destroy_path: "/registries/{id}",
          create_method: "",
          read_method: "",
          update_method: "",
          destroy_method: "",
          id_attribute: "domain",
          object_id: $reg.domain,
          data: $data,
          read_data: "",
          update_data: "",
          destroy_data: "",
          debug: false,
          read_search: {
            results_key: "result",
            search_key: "domain",
            search_value: $reg.domain
          },
          query_string: "",
          api_data: {},
          api_response: "",
          create_response: "",
          force_new: [
            $reg.domain,
            $reg.public_key,
            $reg.private_credential.store_id,
            $reg.private_credential.secret_name
          ],
          ignore_changes_to: [],
          ignore_all_server_changes: true
        },
        sensitive_attributes: [],
        dependencies: [
          "cloudflare_secrets_store_secret.gar_key",
          "data.cloudflare_secrets_stores.all",
          "google_service_account.image_pull",
          "google_service_account_key.image_pull"
        ]
      }]
    }]
' "$backup" > gar-registry-fixed.tfstate

tofu state push gar-registry-fixed.tfstate
echo "pushed; verifying:"
tofu plan
