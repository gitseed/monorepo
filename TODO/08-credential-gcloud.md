# Wire Google Cloud credentials

## Why

The OpenTofu Google provider needs application-default credentials (ADC) to
manage Cloud Build, Artifact Registry, and service accounts. The `gcloud`
CLI also needs auth for `gcloud builds submit`.

- `tofu/tofu.tf`: `provider "google" { project = "untrusted-agent" }` — reads
  Google credentials via the standard ADC chain.
- `tofu/image.tf`: uses `terraform_data` provisioner to run `gcloud builds submit`.
- `tofu/registries.tf`: creates service accounts and keys.

## What to do

### Option A: Service account key (recommended for automation)

Store a Google service account JSON key as a secret and activate it at
container startup:

1. **Create a service account** in the `untrusted-agent` project with roles:
   - `roles/cloudbuild.builds.editor` — trigger Cloud Build
   - `roles/artifactregistry.writer` — push images to Artifact Registry
   - `roles/iam.serviceAccountAdmin` — create the image-pull SA (tofu)
   - `roles/iam.serviceAccountKeyAdmin` — create keys for the pull SA (tofu)

2. **Store the key JSON** in Infisical as `google_application_credentials`.

3. **Wire into the sandbox**:

   In `sandbox.containerfile`:
   ```dockerfile
   ENV GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json
   ```

   In `entrypoint.sh` or a first-run script:
   ```bash
   echo "$GOOGLE_SA_KEY" > /root/.config/gcloud/application_default_credentials.json
   gcloud auth activate-service-account --key-file=/root/.config/gcloud/adc.json
   ```

### Option B: Interactive login (for development)

Run `gcloud auth login` and `gcloud auth application-default login` manually
after container start. This opens a browser flow (not possible in the
headless sandbox) unless using `--no-launch-browser` with a manual URL.

**Option A is strongly preferred** for the sandbox.

## Envoy proxy considerations

Google Cloud APIs (`*.googleapis.com`, `cloudbuild.googleapis.com`,
`artifactregistry.googleapis.com`) may need proxying if the sandbox
network blocks direct outbound. Add upstreams in `envoy.pkl`:

```pkl
new {
    host = "cloudbuild.googleapis.com"
    name = "gcloud_cloudbuild"
    secret = "google_oauth_token"
    env = "GOOGLE_OAUTH_TOKEN"
    // Google uses Bearer tokens
}
new {
    host = "artifactregistry.googleapis.com"
    name = "gcloud_ar"
    secret = "google_oauth_token"
    env = "GOOGLE_OAUTH_TOKEN"
}
```

However, `gcloud` uses its own credential management — it doesn't send an
`Authorization` header from an env var the way Envoy expects. The cleaner
approach is to use the service account key directly (Option A) and let gcloud
handle auth internally, while proxying the Google API hostnames only for
network routing (if needed).

See [`11-proxy-upstreams.md`](11-proxy-upstreams.md) for the shared proxy
work.

## Acceptance

```bash
gcloud auth list  # shows the service account
gcloud auth application-default print-access-token  # succeeds
# tofu apply in veronica/tofu reaches Google Cloud
```
