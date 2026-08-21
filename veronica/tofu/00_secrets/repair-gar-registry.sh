#!/usr/bin/env bash
# Reconstruct state entries for resources in 00_secrets from live Cloudflare APIs:
# 1. restapi_object.gar_registry (no per-object GET in Containers registries API)
# 2. cloudflare_secrets_store_secret.gar_key (looks up the secret's UUID by name)
#
# Safe to delete or re-run once `tofu plan` shows no changes.
set -euo pipefail
cd "$(dirname "$0")"

ACCOUNT_ID=287cae24e46a0aeed1dbc2942fc58dd7
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN must be set}"

# 1. Fetch registry info
reg=$(
  curl -fsS -H @<(printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN") \
    "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/containers/registries" \
  | python3 -c '
import sys, json
data = json.load(sys.stdin)
matches = [r for r in data.get("result", []) if r.get("kind") == "GAR"]
if not matches:
    sys.exit("No GAR registry found")
print(json.dumps(matches[0]))
'
)

# 2. Fetch secrets store secret info by store_id and secret name
store_id=$(python3 -c 'import sys, json; print(json.loads(sys.argv[1])["private_credential"]["store_id"])' "$reg")
secret_name=$(python3 -c 'import sys, json; print(json.loads(sys.argv[1])["private_credential"]["secret_name"])' "$reg")

secret_info=$(
  curl -fsS -H @<(printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN") \
    "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/secrets_store/stores/${store_id}/secrets" \
  | python3 -c '
import sys, json
data = json.load(sys.stdin)
name = sys.argv[1]
matches = [s for s in data.get("result", []) if s.get("name") == name]
if not matches:
    sys.exit(f"No secret named {name} found in store {sys.argv[2]}")
print(json.dumps(matches[0]))
' "$secret_name" "$store_id"
)

secret_id=$(python3 -c 'import sys, json; print(json.loads(sys.argv[1])["id"])' "$secret_info")
echo "Found secret $secret_name with ID $secret_id in store $store_id"

backup="secrets-backup-$(date +%Y%m%d%H%M%S).tfstate"
tofu state pull > "$backup"
echo "state backed up to $backup"

python3 -c '
import sys, json

backup_file = sys.argv[1]
reg = json.loads(sys.argv[2])
secret = json.loads(sys.argv[3])
account_id = sys.argv[4]

with open(backup_file) as f:
    state = json.load(f)

# Compact JSON string for restapi_object.gar_registry data
data_dict = {
    "auth": {
        "private_credential": {
            "secret_name": reg["private_credential"]["secret_name"],
            "store_id": reg["private_credential"]["store_id"]
        },
        "public_credential": reg.get("public_credential") or reg.get("public_key")
    },
    "domain": reg["domain"],
    "is_public": False,
    "kind": "GAR"
}
data_str = json.dumps(data_dict, separators=(",", ":"))

state["serial"] = state.get("serial", 0) + 1

# Filter out existing entries for gar_registry and gar_key
resources = [
    r for r in state.get("resources", [])
    if not (r.get("type") == "restapi_object" and r.get("name") == "gar_registry")
    and not (r.get("type") == "cloudflare_secrets_store_secret" and r.get("name") == "gar_key")
]

# Add gar_key resource
resources.append({
    "mode": "managed",
    "type": "cloudflare_secrets_store_secret",
    "name": "gar_key",
    "provider": "provider[\"registry.opentofu.org/cloudflare/cloudflare\"]",
    "instances": [{
        "schema_version": 0,
        "attributes": {
            "account_id": account_id,
            "comment": f"Created by OpenTofu: credentials for image registry {reg[\"domain\"]}",
            "created": secret.get("created"),
            "dependencies": [
                "data.cloudflare_secrets_stores.all",
                "google_service_account.image_pull",
                "google_service_account_key.image_pull"
            ],
            "id": secret["id"],
            "modified": secret.get("modified"),
            "name": secret["name"],
            "scopes": secret.get("scopes", ["containers"]),
            "sensitive_attributes": [
                [{"type": "get_attr", "value": "value"}]
            ],
            "status": secret.get("status", "active"),
            "store_id": secret.get("store_id", reg["private_credential"]["store_id"]),
            "value": None
        }
    }]
})

# Add gar_registry resource
resources.append({
    "mode": "managed",
    "type": "restapi_object",
    "name": "gar_registry",
    "provider": "provider[\"registry.opentofu.org/mastercard/restapi\"].cloudflare_containers",
    "instances": [{
        "schema_version": 0,
        "attributes": {
            "id": reg["domain"],
            "path": "/registries",
            "create_path": "",
            "read_path": "/registries",
            "update_path": "",
            "destroy_path": "/registries/{id}",
            "create_method": "",
            "read_method": "",
            "update_method": "",
            "destroy_method": "",
            "id_attribute": "domain",
            "object_id": reg["domain"],
            "data": data_str,
            "read_data": "",
            "update_data": "",
            "destroy_data": "",
            "debug": False,
            "read_search": {
                "results_key": "result",
                "search_key": "domain",
                "search_value": reg["domain"]
            },
            "query_string": "",
            "api_data": {},
            "api_response": "",
            "create_response": "",
            "force_new": [
                reg["domain"],
                reg.get("public_credential") or reg.get("public_key"),
                reg["private_credential"]["store_id"],
                reg["private_credential"]["secret_name"]
            ],
            "ignore_changes_to": [],
            "ignore_all_server_changes": True
        },
        "sensitive_attributes": [],
        "dependencies": [
            "cloudflare_secrets_store_secret.gar_key",
            "data.cloudflare_secrets_stores.all",
            "google_service_account.image_pull",
            "google_service_account_key.image_pull"
        ]
    }]
})

state["resources"] = resources

with open("secrets-fixed.tfstate", "w") as f:
    json.dump(state, f, indent=2)
' "$backup" "$reg" "$secret_info" "$ACCOUNT_ID"

tofu state push secrets-fixed.tfstate
echo "state pushed; verifying with plan:"
tofu plan
