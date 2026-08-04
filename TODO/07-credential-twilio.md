# Wire TWILIO_API_KEY / TWILIO_API_SECRET

## Why

The OpenTofu Twilio provider requires Twilio credentials to manage the phone
number resource.

- `tofu/tofu.tf`: `provider "twilio" {}` reads `TWILIO_API_KEY` /
  `TWILIO_API_SECRET` from the environment (falling back to
  `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN`).

## What to do

Twilio has two API surfaces:

1. **REST API** (`api.twilio.com` / `www.twilio.com`) — used by the provider
   for resource management.
2. **Console** (`www.twilio.com`) — for call log access.

### 1. Add upstream in `envoy.pkl`

```pkl
new {
    host = "api.twilio.com"
    name = "twilio"
    secret = "twilio_api_key"
    env = "TWILIO_API_KEY"
}
```

Twilio uses HTTP Basic auth (SID:token), not Bearer. The Envoy credential
injector adds an `Authorization` header. Twilio's auth header format is
`Authorization: Basic base64(SID:token)`. This may require:

- A custom Envoy filter configuration, or
- Using the `prefix = "Basic "` option in the Upstream class (already
  supported — see the `github_git` upstream for precedent).

### 2. Add to cert SAN in `credentials_proxy_cert.tf`

Add `"api.twilio.com"` to the `dns_names` list.

### 3. Add to `compose.yml`

```yaml
# proxy service environment:
- TWILIO_API_KEY
- TWILIO_API_SECRET

# sandbox service links:
- "proxy:api.twilio.com"
```

### 4. Add placeholder ENV in `sandbox.containerfile`

```dockerfile
ENV TWILIO_API_KEY=dummy-replaced-by-proxy
ENV TWILIO_API_SECRET=dummy-replaced-by-proxy
```

### 5. Add secrets to Infisical

Add `twilio_api_key` and `twilio_api_secret` to the Infisical project.

## Complexity: Twilio auth format

Twilio REST API uses HTTP Basic auth: `Authorization: Basic base64(AccountSID:AuthToken)`.

The Twilio **API Key** is a separate credential (`SK...` + secret) used as
`AccountSID:APIKeySecret` in Basic auth. The tofu provider accepts either
`TWILIO_API_KEY`/`TWILIO_API_SECRET` or `TWILIO_ACCOUNT_SID`/`TWILIO_AUTH_TOKEN`.

The Envoy credential injector currently supports a single `Authorization`
header with a configurable prefix. For Twilio Basic auth, the credential
value must be `base64(SID:token)`, not the raw token. Options:

1. **Pre-encode the Basic auth value** in Infisical as
  `base64(SID:secret)` and inject it with `prefix = "Basic "`.
2. **Use account SID + auth token** env vars and accept that the proxy
   pattern doesn't cleanly support Twilio's multi-value auth.

Option 1 is cleaner and fits the existing pattern.

## Acceptance

```bash
echo $TWILIO_API_KEY  # dummy value
curl -sI https://api.twilio.com/ | head -5
# 200/401 from the proxy means the credential is being injected
```
