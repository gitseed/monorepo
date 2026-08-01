Read only secrets for AI agent consumption.

This repo is using the tofu-sensitive state bucket, because it has secrets, so agents can't plan against it.

Because we have the admin credentials from ouroboros, we can create many credentials automatically, but not all.

Tofu-managed secrets in the `agent` project:
* `OPENROUTER_API_KEY` (openrouter.tf): provisioned API key, injected into envoy by the credentials-proxy.
* `CREDENTIALS_PROXY_CA_CERT` / `CREDENTIALS_PROXY_CA_KEY` / `CREDENTIALS_PROXY_SERVER_CERT` / `CREDENTIALS_PROXY_SERVER_KEY` (credentials_proxy_cert.tf): TLS for the sandbox <-> proxy interception endpoint. Envoy receives the server cert+key purely through its environment (credentials-proxy/run.sh); the sandbox image build fetches the public CA cert via credentials-proxy/fetch-ca-cert.sh. Private keys never leave state/vault/env.

Manually created credentials:
* Github read only PAT: Github is literally the worst don't even get me started.