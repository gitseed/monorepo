# Veronica's tofu layers

Two layers, applied in numeric order (see the [skill](../../.agents/skills/tofu-architecture/SKILL.md)):

| Layer | Bucket | State | Applied by |
| --- | --- | --- | --- |
| `00_secrets/` | `tofu-sensitive` | Holds secrets: the image-pull SA key, the Secrets Store secret, the registries token | Human only |
| `01_app/` | `tofu` | Secret-free, so sandbox agents can plan and apply it | Agent or human |

The split follows the secrets rule: if `tofu show -json` would reveal a
credential, the resource belongs in `00_secrets`. Everything else — KV,
zone SSL, Twilio number, Artifact Registry repository, Cloud Build image,
wrangler render — stays plannable in `01_app`.

The layers are wired only by stable names, never by reading each other's
state: `01_app` grants `roles/artifactregistry.reader` to
`voice-pull-<workspace>@<project>.iam.gserviceaccount.com`, and
`00_secrets` constructs the same repository path and SA name from its own
copy of the workspace settings (`workspaces.tf` in each layer). Keep the
two `workspaces.tf` files' shared fields identical.

Apply order matters: `00_secrets` creates the pull SA that `01_app`'s
grant names, so apply `00_secrets` first, then `01_app`. Destroy in
reverse.

## Migrating the pre-split deployment (one-time)

The old single-layer root kept all state under key `tofu` in the
agent-readable bucket. To move it:

1. From a checkout of the pre-split revision, with the `veronica`
   workspace selected and the backend configured:

   ```bash
   tofu state pull > /tmp/veronica-old.json
   ```

2. Split the resources (adjust the jq lists if addresses changed):

   ```bash
   SECRET_TYPES='"google_project_service.services","google_service_account.image_pull","google_service_account_key.image_pull","cloudflare_secrets_stores.all","cloudflare_secrets_store_secret.gar_key","cloudflare_api_token_permission_groups_list.account_scope","cloudflare_account_token.registry","restapi_object.gar_registry"'

   jq --argjson keep "[$SECRET_TYPES]" \
     '{version, terraform_version, serial: 1, lineage, outputs: {},
       resources: [.resources[] | select("\(.type).\(.name)" as $a | $keep | index($a) | not)]}' \
     /tmp/veronica-old.json > /tmp/veronica-app.json

   jq --argjson move "[$SECRET_TYPES]" \
     '{version, terraform_version, serial: 1, lineage, outputs: {},
       resources: [.resources[] | select("\(.type).\(.name)" as $a | $move | index($a))]}' \
     /tmp/veronica-old.json > /tmp/veronica-secrets.json
   ```

3. Push each half into its layer's new state key (`00_secrets` / `01_app`,
   per the backend `key = basename(abspath(path.module))`). The push into
   `tofu-sensitive` needs the human's credentials — agents cannot read or
   write that bucket by design.

   ```bash
   cd tofu/00_secrets && tofu init && tofu workspace select veronica
   cat /tmp/veronica-secrets.json | tofu state push -force -

   cd ../01_app && tofu init && tofu workspace select veronica
   cat /tmp/veronica-app.json | tofu state push -force -
   ```

4. Confirm with `tofu plan` in both layers: both should come back clean
   (or with only expected diffs from the reorganization). Delete the old
   `tofu` state object from the readable bucket once both plans are clean —
   it contains the SA key and token.
