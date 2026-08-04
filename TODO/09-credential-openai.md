# Wire OPENAI_API_KEY

## Why

The OpenAI API key is uploaded as a Worker secret via `wrangler secret put`.
It's also needed for any local development or testing against the OpenAI
Realtime API.

- `app/SETUP.md` step 5: `npx wrangler secret put OPENAI_API_KEY`
- The Realtime API requires billing-enabled API access

## What to do

This credential is used in two ways:

### 1. Wrangler secret upload (one-time)

`wrangler secret put OPENAI_API_KEY` sends the key to the Cloudflare Worker
secret store. This requires the key to be available in the shell (or piped
in), but does NOT need to be proxied — it goes through wrangler (which uses
`CLOUDFLARE_API_TOKEN` to the Cloudflare API).

### 2. Direct API access (development/testing)

If you need to call the OpenAI API directly (e.g., for testing the Realtime
SIP integration, or platform.openai.com webhook setup), you need
`OPENAI_API_KEY` available as an environment variable.

#### Option A: Envoy proxy (recommended)

```pkl
// envoy.pkl
new {
    host = "api.openai.com"
    name = "openai"
    secret = "openai_api_key"
    env = "OPENAI_API_KEY"
}
```

Add `api.openai.com` to the cert SAN, compose links, and containerfile
placeholder ENV — same 4-file pattern as the other credentials.

#### Option B: Direct env var

If the sandbox has direct outbound access to `api.openai.com` (not proxied),
just set the env var:

```dockerfile
ENV OPENAI_API_KEY=dummy-replaced-by-proxy
```

And provide the real key through the proxy.

### 3. Webhook signing secret

Separately, `OPENAI_WEBHOOK_SECRET` is also uploaded via
`wrangler secret put`. This is not an API credential and doesn't need
proxying — it's only used for HMAC verification of incoming webhooks.

## Acceptance

```bash
echo $OPENAI_API_KEY  # dummy or real
# wrangler secret put succeeds
# curl https://api.openai.com/v1/models succeeds with injected Bearer token
```
