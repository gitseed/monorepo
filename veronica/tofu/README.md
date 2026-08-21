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

The old single-layer root left everything under state key `tofu`. Each
layer adopts what it owns with `import` blocks — the same pattern
`twilio.tf` uses for the phone number — so no state file is ever pulled,
edited, or pushed by hand.

Paste the blocks for a layer into a temporary `migrate.tf` there, fill in
the IDs, `tofu apply`, confirm the following plan is clean, then delete
`migrate.tf`. Fresh deploys skip all of this. Fetch IDs from the consoles
or `gcloud` — not `tofu show` on the old root, which prints the SA key
and token to the terminal. (`contacts_namespace_id` is safe: it is the
old root's non-secret output.)

### tofu/01_app

```hcl
import {
  to = google_project_service.services["artifactregistry.googleapis.com"]
  id = "artifactregistry.googleapis.com"
}
# one more per service: cloudbuild, iam, logging, storage

import {
  to = google_artifact_registry_repository.voice
  id = "projects/untrusted-agent/locations/us-central1/repositories/veronica"
}

import {
  to = google_service_account.build
  id = "voice-build-veronica@untrusted-agent.iam.gserviceaccount.com"
}

import {
  to = google_project_iam_member.build_builds
  id = "untrusted-agent roles/cloudbuild.builds.builder serviceAccount:voice-build-veronica@untrusted-agent.iam.gserviceaccount.com"
}

import {
  to = google_artifact_registry_repository_iam_member.build_pushes
  id = "projects/untrusted-agent/locations/us-central1/repositories/veronica roles/artifactregistry.writer serviceAccount:voice-build-veronica@untrusted-agent.iam.gserviceaccount.com"
}

import {
  to = google_artifact_registry_repository_iam_member.cloudflare_pulls
  id = "projects/untrusted-agent/locations/us-central1/repositories/veronica roles/artifactregistry.reader serviceAccount:voice-pull-veronica@untrusted-agent.iam.gserviceaccount.com"
}

import {
  to = cloudflare_workers_kv_namespace.contacts
  id = "<namespace id>"
}

import {
  to = cloudflare_zone_setting.voice_ssl
  id = "<zone id>/ssl"
}
```

The Twilio number needs nothing — its `import` block in `twilio.tf`
carries over unchanged. `local_file.wrangler_config` and `time_sleep` are
not imported: both recreate instantly and harmlessly, and
`terraform_data.image` re-runs once, re-pushing the same content-addressed
tag.

### tofu/00_secrets

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

If a provider rejects an ID format, adjust it per that provider's import
docs — the block takes exactly the ID `tofu import` would.

Once both layers plan clean, delete the old `tofu` state object from the
readable bucket — it still contains the SA key and the token.
