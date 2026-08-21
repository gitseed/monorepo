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

1. In 01_app, forget the resources that moved to 00_secrets using
   `removed` blocks (with `destroy = false` so OpenTofu drops them
   from state without deleting the real infrastructure). Paste into a
   temporary `migrate.tf` there, apply to update state, then delete
   `migrate.tf`:

   ```hcl
   removed {
     from = google_project_service.services
     lifecycle {
       destroy = false
     }
   }

   removed {
     from = google_service_account.image_pull
     lifecycle {
       destroy = false
     }
   }

   removed {
     from = google_service_account_key.image_pull
     lifecycle {
       destroy = false
     }
   }

   removed {
     from = cloudflare_secrets_store_secret.gar_key
     lifecycle {
       destroy = false
     }
   }

   removed {
     from = cloudflare_account_token.registry
     lifecycle {
       destroy = false
     }
   }

   removed {
     from = restapi_object.gar_registry
     lifecycle {
       destroy = false
     }
   }
   ```

2. In 00_secrets:
   - `google_service_account.image_pull` and `google_project_service.services`
     have static `import` blocks directly in `registries.tf` (mirroring the
     pattern `twilio.tf` uses for the Twilio phone number), so they are
     adopted automatically on apply.
   - For `restapi_object.gar_registry`, the Cloudflare Containers registries
     API is list-only with no per-object GET endpoint (which breaks `tofu import`).
     Run `00_secrets/repair-gar-registry.sh` to reconstruct its state entry
     directly from the live API record.
   - The pull service account key, Secrets Store secret, and scoped account
     token are minted fresh on apply, avoiding manual key export or token copying.

One caveat: with versioning enabled on the readable bucket, older
revisions of its state object still contain the removed secrets until
they expire — purge old versions if that matters for you.

Fresh deploys skip step 1.
