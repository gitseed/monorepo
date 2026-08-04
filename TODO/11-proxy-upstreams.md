# Add Envoy proxy upstreams for new API hostnames

## Why

Veronica development requires the sandbox to reach several external APIs
that aren't currently proxied. The credentials-proxy pattern (Envoy +
compose links + cert SAN + containerfile ENV) must be extended for each
new hostname.

## Current proxy upstreams

| Hostname | Secret | Env Var |
|----------|--------|---------|
| `openrouter.ai` | `openrouter_api_key` | `OPENROUTER_API_KEY` |
| `api.github.com` | `github_token` | `GITHUB_TOKEN` |
| `github.com` | `github_token_basic` | `GITHUB_TOKEN_BASIC` |
| `api.firecrawl.dev` | `firecrawl_api_key` | `FIRECRAWL_API_KEY` |

## New upstreams needed for veronica

| Hostname | Secret | Env Var | Auth | File |
|----------|--------|---------|------|------|
| `api.cloudflare.com` | `cloudflare_api_token` | `CLOUDFLARE_API_TOKEN` | Bearer | [06](06-credential-cloudflare.md) |
| `api.twilio.com` | `twilio_api_key` | `TWILIO_API_KEY` | Basic | [07](07-credential-twilio.md) |
| `*.googleapis.com` | `google_oauth_token` | `GOOGLE_OAUTH_TOKEN` | Bearer | [08](08-credential-gcloud.md) |
| `api.openai.com` | `openai_api_key` | `OPENAI_API_KEY` | Bearer | [09](09-credential-openai.md) |

## What to do (per upstream)

Each new upstream requires changes to **4 files** (the established pattern):

### 1. `omp-sandbox/container/envoy.pkl`

Add a new `Upstream` entry to the `upstreams` listing.

### 2. `agent-secrets/tofu/credentials_proxy_cert.tf`
Add the hostname to the `dns_names` list in the TLS certificate SAN.

### 3. `omp-sandbox/compose.yml`
- Add the secret env var to the `proxy` service's `environment`.
- Add the `proxy:<hostname>` link to the `sandbox` service's `links`.

### 4. `omp-sandbox/container/sandbox.containerfile`
Add a placeholder `ENV` line so the tool considers itself available.

### 5. Infisical
Add the secret value to Infisical so it flows through the pipeline.

## Deployment

After all upstreams are added:

1. `tofu apply` in `agent-secrets/tofu/` — re-signs the cert with the new
   SANs.
2. Rebuild the sandbox container — picks up the new envoy config and compose
   links.

## Notes

- **Twilio uses Basic auth** — use the `prefix = "Basic "` option in the
  Upstream class (precedent: `github_git` upstream).
- **Google APIs are spread across multiple hostnames** —
  `cloudbuild.googleapis.com`, `artifactregistry.googleapis.com`,
  `iam.googleapis.com`, etc. Consider whether each needs its own upstream
  or if a wildcard `*.googleapis.com` approach works (Envoy SNI matching
  is exact, so each hostname likely needs its own entry).
- **R2 state backend** (`*.r2.cloudflarestorage.com`) uses S3 signature
  auth, not Bearer — see [10-credential-r2-backend.md](10-credential-r2-backend.md)
  for why this is wired differently (direct credentials, not proxy).
- **OpenAI webhook secret** (`OPENAI_WEBHOOK_SECRET`) is NOT an API
  credential — it's an HMAC key for verifying incoming webhooks. It doesn't
  need proxying.

## Acceptance

```bash
# All proxied APIs return 200/401 (not connection refused):
curl -sI https://api.cloudflare.com/client/v4/user/tokens/verify | head -1
curl -sI https://api.twilio.com/ | head -1
curl -sI https://api.openai.com/v1/models | head -1
```
