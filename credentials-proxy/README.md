# credentials-proxy

Envoy with the credential-injector filter: callers authenticate with anything
(or nothing); the real OpenRouter key is attached on this side of the
boundary. The key arrives via `infisical run` and only ever exists in this
container's environment — never in the sandbox, never on disk.

The companion piece is `../omp-sandbox/`: its `scripts/up.sh` builds both
images and runs a session (this proxy in the background, the sandbox in the
foreground; both torn down on exit). This README covers the proxy when run
standalone.

## Listeners

Both inject the same credential (`overwrite: true`):

- `127.0.0.1:10000` (plain HTTP, host only) — debugging with curl.
- `:443` (TLS, cert for openrouter.ai) — the sandbox resolves openrouter.ai
  to this container's address, so stock clients use the real
  https://openrouter.ai endpoint unchanged.

## Certificates

Tofu-managed (`../agent-secrets/tofu/credentials_proxy_cert.tf`) and stored
in infisical. The proxy gets the server cert+key via its environment; the
sandbox image gets the public CA cert as a build secret. No cert files on
disk or in git. Rotate: apply the tofu; the next `up.sh` run rebuilds the
sandbox image (daily staleness) and starts a proxy with the new material.

## Networking note

OrbStack runs container DNS through the host's resolver stack, so upstream
resolution keeps working under Cloudflare WARP (the `--dns <host dnsmasq>`
work-around from the apple/container era is gone). In *this* container
openrouter.ai must resolve to the real upstream; only the sandbox remaps it
(to the proxy, via /etc/hosts).

## Manual debug proxy

`up.sh` runs a per-session proxy. For a long-lived one instead:

    infisical run -- \
      docker run --rm -d --name credentials-proxy \
        -p 127.0.0.1:10000:10000 \
        --network agent \
        --env OPENROUTER_API_KEY --env CREDENTIALS_PROXY_SERVER_CERT \
        --env CREDENTIALS_PROXY_SERVER_KEY \
        credentials-proxy

(The `-p` publish is what makes the 127.0.0.1:10000 check below work from
the host; session proxies from `up.sh` don't need it -- the sandbox talks to
the proxy's container IP directly, which OrbStack routes from guest to guest.)

## Quick checks

PROXY_IP = a live session proxy's address (`docker ps` + `docker inspect`, or
grab it from `up.sh`'s startup output).

    # plain-HTTP listener; injected key turns a bogus header into a 200
    curl --fail-with-body --silent --show-error \
      -H 'Authorization: wrong' http://127.0.0.1:10000/api/v1/auth/key

    # TLS listener, exactly as the sandbox sees it
    curl --fail-with-body --silent --show-error \
      --cacert <(infisical secrets get CREDENTIALS_PROXY_CA_CERT --plain) \
      --resolve openrouter.ai:443:PROXY_IP \
      -H 'Authorization: wrong' https://openrouter.ai/api/v1/auth/key

Control (must be 401): `curl https://openrouter.ai/api/v1/auth/key`
