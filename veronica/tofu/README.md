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

01_app's state does not move. Its backend pins the pre-split root's
state object (`key = "tofu"`), so every resource it owned keeps the
exact state it always had: init, select the workspace, plan clean.
The Twilio number's `import` block in `twilio.tf` rides along unused —
the number was imported into this state long ago.

Only the credential chain leaves for 00_secrets, in two steps.

1. In 01_app, stop tracking what moved. This removes state entries
   only — it never touches a real resource:

   ```bash
   cd tofu/01_app && tofu init && tofu workspace select veronica
   tofu state rm \
     google_project_service.services \
     google_service_account.image_pull \
     google_service_account_key.image_pull \
     cloudflare_secrets_stores.all \
     cloudflare_secrets_store_secret.gar_key \
     cloudflare_api_token_permission_groups_list.account_scope \
     cloudflare_account_token.registry \
     restapi_object.gar_registry
   ```

2. Adopt them in 00_secrets with import blocks — the same pattern
   `twilio.tf` uses for the phone number. Paste into a temporary
   `migrate.tf` there, fill in the IDs, apply, confirm the following
   plan is clean, then delete `migrate.tf`. (The two data sources need
   nothing; they refresh at plan time.)

   ```hcl
   import {
     to = google_service_account.image_pull
     id = "voice-pull-veronica@untrusted-agent.iam.gserviceaccount.com"
   }

   import {
     to = google_service_account_key.image_pull
     id = "projects/untrusted-agent/serviceAccounts/voice-pull-veronica@untrusted-agent.iam.gserviceaccount.com/keys/<key id — gcloud iam service-accounts keys list --iam-account=voice-pull-veronica@untrusted-agent.iam.gserviceaccount.com>"
   }

   import {
     to = cloudflare_account_token.registry
     id = "<token id — Cloudflare dashboard, Account API Tokens>"
   }

   import {
     to = cloudflare_secrets_store_secret.gar_key
     id = "<account id>/<store id>/veronica-gar-pull"
   }

   import {
     to = restapi_object.gar_registry
     id = "us-central1-docker.pkg.dev"
   }
   ```

Fetch IDs from the consoles or `gcloud` — never `tofu show` before
step 1 removes them from 01_app's state, which prints the SA key and
token to the terminal. If a provider rejects an ID format, use whatever
`tofu import` would take.

One caveat: with versioning enabled on the readable bucket, older
revisions of its state object still contain the removed secrets until
they expire — purge old versions if that matters for you.

Fresh deploys skip everything above.
