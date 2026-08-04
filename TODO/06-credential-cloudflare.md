# Wire CLOUDFLARE_API_TOKEN

## Why

Both the OpenTofu Cloudflare provider and wrangler require
`CLOUDFLARE_API_TOKEN`:

- **Tofu provider** (`tofu/tofu.tf`): `provider "cloudflare" {}` reads
  `CLOUDFLARE_API_TOKEN` from the environment. Needs edit access to Workers
  scripts, KV, Containers, and the `veronica-agent.com` zone.
- **Wrangler** (`app/`): uses `CLOUDFLARE_API_TOKEN` (or `wrangler login`)
  to deploy Workers and put secrets.

## What to do

Follow the existing credentials-proxy pattern used for OpenRouter, GitHub,
and Firecrawl:

### 1. Add upstream in `envoy.pkl`

```pkl
new {
    host = "api.cloudflare.com"
    name = "cloudflare"
    secret = "cloudflare_api_token"
    env = "CLOUDFLARE_API_TOKEN"
}
```

### 2. Add to cert SAN in `agent-secrets/tofu/credentials_proxy_cert.tf`

Add `"api.cloudflare.com"` to the `dns_names` list.

### 3. Add to `compose.yml`

```yaml
# proxy service environment:
- CLOUDFLARE_API_TOKEN

# sandbox service links:
- "proxy:api.cloudflare.com"
```

### 4. Add placeholder ENV in `sandbox.containerfile`

```dockerfile
ENV CLOUDFLARE_API_TOKEN=dummy-replaced-by-proxy
```

### 5. Add secret to Infisical

Add `cloudflare_api_token` as an secret in the Infisical project so it flows
through `infisical run` → host env → proxy container → Envoy injector.

## Notes

- The Cloudflare API token needs broad permissions (Workers, KV, Containers,
  DNS, Zones). The exact scope depends on the tofu resources.
- Wrangler may also need `CLOUDFLARE_ACCOUNT_ID` — the workspace config in
  `tofu/workspace.tf` sets `cloudflare_account_id = "287cae24e46a0aeed1dbc2942fc58dd7"`.

## Acceptance

```bash
echo $CLOUDFLARE_API_TOKEN  # dummy value (proxy injects real one)
curl -sI https://api.cloudflare.com/client/v4/user/tokens/verify | head -5
# 200 from the proxy means the token is being injected
```
