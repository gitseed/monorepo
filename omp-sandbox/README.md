# omp-sandbox

The omp coding agent in an [apple/container](https://github.com/apple/container)
sandbox with **no leakable credentials inside**.

```mermaid
flowchart LR
    subgraph sandbox[omp-sandbox container]
        omp[omp + any HTTPS client] -->|"/etc/hosts: openrouter.ai -> proxy IP"| t[TLS via local CA]
    end
    t -->|https://openrouter.ai ... but really the proxy| envoy
    subgraph proxy[credentials-proxy container]
        envoy[envoy :443] -->|"credential_injector overwrites Authorization"| real[https://openrouter.ai real IP]
    end
```

- The sandbox carries only a **dummy** `OPENROUTER_API_KEY`
  (`dummy-replaced-by-proxy`) so omp considers the provider available.
- The sandbox resolves `openrouter.ai` to the **proxy container's** address
  (`/etc/hosts`, written by the entrypoint from `$OPENROUTER_PROXY_IP`).
- The proxy terminates TLS with a tofu-issued, infisical-stored cert handed
  to envoy purely via its environment, no key material on disk (the sandbox
  image bakes the CA into its trust store, plus `NODE_EXTRA_CA_CERTS` for Bun),
  **overwrites** the `Authorization` header with the real key, and forwards
  to actual openrouter.ai, which in *that* container resolves to the real IP.
- Bypass test: from inside the sandbox, hitting the real openrouter.ai IP
  directly with the in-sandbox key returns 401. There is nothing to leak.

## Run

```sh
./up.sh                     # one command from cold: images + proxy, then interactive omp
./up.sh --build             # force a --no-cache sandbox rebuild (after cert rotation)
./up.sh bash                # plain shell instead of omp
WORKSPACE=~/project ./up.sh
```

Idempotent: the proxy start no-ops when already running, images are built
only when missing (or with `--build`). Pieces individually:
`../credentials-proxy/build.sh` / `run.sh`, `./build.sh` / `./run.sh`.

`run.sh` discovers the proxy's current address via `container inspect` and
injects it as `OPENROUTER_PROXY_IP`; the sandbox entrypoint maps
`openrouter.ai` there. Re-run whenever the proxy restarts (its IP changes);
a running sandbox must be restarted too.

## Verified

- `omp -p ... --model openrouter/anthropic/claude-haiku-4.5` inside the
  sandbox answers through the proxy (real key never present).
- `Authorization: Bearer bogus` through the proxy → 200 (overwrite works).
- Direct to the real endpoint with the sandbox's key → 401.
