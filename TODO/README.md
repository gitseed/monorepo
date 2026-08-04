# TODO — Sandbox Environment for Veronica Development

This directory tracks the environment improvements required to clone, build,
test, and deploy [veronica](https://github.com/paulcdejean/veronica) from
the OMP sandbox. Each file covers one independent piece of work.

## Files

| File | What | Tools / Credentials |
|------|------|---------------------|
| [01-install-go.md](01-install-go.md) | Install Go 1.26 toolchain | `go`, `gofmt` |
| [02-install-node-npm.md](02-install-node-npm.md) | Install Node 22+ and npm | `node`, `npm`, `npx` |
| [03-install-opentofu.md](03-install-opentofu.md) | Install OpenTofu 1.12.3 | `tofu` |
| [04-install-gcloud.md](04-install-gcloud.md) | Install Google Cloud CLI | `gcloud` |
| [05-install-wrangler.md](05-install-wrangler.md) | Install Cloudflare Wrangler | `wrangler` |
| [06-credential-cloudflare.md](06-credential-cloudflare.md) | Wire CLOUDFLARE_API_TOKEN | Envoy proxy upstream |
| [07-credential-twilio.md](07-credential-twilio.md) | Wire TWILIO_API_KEY / SECRET | Envoy proxy upstream |
| [08-credential-gcloud.md](08-credential-gcloud.md) | Wire Google ADC credentials | Envoy proxy upstream |
| [09-credential-openai.md](09-credential-openai.md) | Wire OPENAI_API_KEY | Envoy proxy upstream |
| [10-credential-r2-backend.md](10-credential-r2-backend.md) | Wire Cloudflare R2 S3 backend | AWS CLI profile |
| [11-proxy-upstreams.md](11-proxy-upstreams.md) | Add proxy upstreams for new APIs | Envoy + cert SAN |

## Context

The veronica repo is a voice agent with two roots:

- **`app/`** — Cloudflare Worker (TypeScript) + Go session-driver container.
  Development requires Node 22+, npm, wrangler, and Go 1.26.
- **`tofu/`** — OpenTofu managing Cloudflare (Workers, KV, Containers), Twilio,
  and Google Cloud (Cloud Build, Artifact Registry). Development requires
  OpenTofu 1.12.3, gcloud CLI, and credentials for all three providers.

All credentials flow through the existing credentials-proxy pattern (Envoy
upstream + `compose.yml` link + `sandbox.containerfile` ENV placeholder),
never reaching the sandbox container directly. See
[`11-proxy-upstreams.md`](11-proxy-upstreams.md) for the shared proxy work.
