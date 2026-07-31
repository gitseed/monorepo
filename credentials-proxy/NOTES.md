# credentials-proxy notes

Envoy with the credential-injector filter: callers authenticate with anything
(or nothing); the real OpenRouter key is attached on this side of the
boundary. The key arrives via infisical and only ever exists in this
container, never in the sandbox.

Two listeners, both injecting the same credential:

- `127.0.0.1:10000` (plain HTTP, host only) — original PoC, handy for
  debugging with curl.
- `:443` (TLS, cert for openrouter.ai from `certs/`) — the sandbox container
  resolves openrouter.ai to this container's address, so stock clients can
  use the real https://openrouter.ai endpoint unchanged.

One-time setup:

    ./generate-certs.sh   # local CA + openrouter.ai server cert; keys gitignored

Build:

    container build --pull --no-cache \
      -t credentials-proxy \
      --dns 203.0.113.113 \
      -f credentials-proxy/main.containerfile \
      credentials-proxy/

Run (detached, on the shared `agent` network; prints the container IP):

    ./run.sh

`--dns 203.0.113.113` routes DNS through the host's dnsmasq, required when
Cloudflare WARP is connected. NOTE: in THIS container openrouter.ai must
resolve to the real upstream — do not let dnsmasq rewrite it. Only the
sandbox gets the proxy address (via its /etc/hosts entry).

Quick checks from the host (IP printed by run.sh):

    # plain-HTTP listener; injected key turns a bogus header into a 200
    curl --fail-with-body --silent --show-error \
      -H 'Authorization: wrong' http://127.0.0.1:10000/api/v1/auth/key

    # TLS listener, exactly as the sandbox sees it
    curl --fail-with-body --silent --show-error \
      --cacert credentials-proxy/certs/ca.pem \
      --resolve openrouter.ai:443:PROXY_IP \
      -H 'Authorization: wrong' https://openrouter.ai/api/v1/auth/key

Control (must be 401): `curl https://openrouter.ai/api/v1/auth/key`

Stop: `container stop credentials-proxy`
