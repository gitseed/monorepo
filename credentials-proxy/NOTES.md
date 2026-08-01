# credentials-proxy notes

Envoy with the credential-injector filter: callers authenticate with anything
(or nothing); the real OpenRouter key is attached on this side of the
boundary. The key arrives via `infisical run` and only ever exists in this
container's environment, never in the sandbox and never on disk.

Two listeners, both injecting the same credential:

- `127.0.0.1:10000` (plain HTTP, host only) — original PoC, handy for
  debugging with curl.
- `:443` (TLS, cert for openrouter.ai) — the sandbox container resolves
  openrouter.ai to this container's address, so stock clients can use the
  real https://openrouter.ai endpoint unchanged. Envoy reads the server
  cert+key straight from its environment; no key material on disk.

Certificates are tofu-managed (`agent-secrets/tofu/credentials_proxy_cert.tf`)
and stored in infisical. The proxy gets the server cert+key purely through
its environment; the sandbox image gets the public CA cert as a build
secret. No cert files anywhere. Rotate by applying the tofu, restarting the
proxy, and rebuilding the sandbox image (the CA is baked into it).

Build and run are handled by `../omp-sandbox/up.sh` (daily-staleness builds;
per-session proxy, torn down on exit). For a manual long-lived debugging
proxy instead:

    infisical run -- \
      container run --rm -d --name credentials-proxy \
        --network agent --dns 203.0.113.113 \
        --env OPENROUTER_API_KEY --env CREDENTIALS_PROXY_SERVER_CERT \
        --env CREDENTIALS_PROXY_SERVER_KEY --env ENVOY_UID=0 \
        credentials-proxy

`--dns 203.0.113.113` routes DNS through the host's dnsmasq, required when
Cloudflare WARP is connected. NOTE: in THIS container openrouter.ai must
resolve to the real upstream — do not let dnsmasq rewrite it. Only the
sandbox gets the proxy address (via its /etc/hosts entry).

Quick checks from the host (PROXY_IP = a live session proxy's address;
`container ls` shows the credentials-proxy-<pid> containers):

    # plain-HTTP listener; injected key turns a bogus header into a 200
    curl --fail-with-body --silent --show-error \
      -H 'Authorization: wrong' http://127.0.0.1:10000/api/v1/auth/key

    # TLS listener, exactly as the sandbox sees it
    curl --fail-with-body --silent --show-error \
      --cacert <(infisical secrets get CREDENTIALS_PROXY_CA_CERT --plain) \
      --resolve openrouter.ai:443:PROXY_IP \
      -H 'Authorization: wrong' https://openrouter.ai/api/v1/auth/key

Control (must be 401): `curl https://openrouter.ai/api/v1/auth/key`
