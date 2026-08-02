# omp-sandbox

The omp coding agent in an [OrbStack](https://orbstack.dev) (docker CLI)
sandbox with **no leakable credentials inside**.

(Previously apple/container; dropped over its bridge-ifnet collision bug,
[apple/container#2051](https://github.com/apple/container/issues/2051),
which silently kills a NAT network's egress.)

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
  (`/etc/hosts`, mapped at container-create time with
  `--add-host openrouter.ai:PROXY_IP`).
- The proxy terminates TLS with a tofu-issued, infisical-stored cert handed
  to envoy purely via its environment, no key material on disk (the sandbox
  image bakes the CA into its trust store, plus `NODE_EXTRA_CA_CERTS` for Bun),
  **overwrites** the `Authorization` header with the real key, and forwards
  to actual openrouter.ai, which in *that* container resolves to the real IP.
- Bypass test: from inside the sandbox, hitting the real openrouter.ai IP
  directly with the in-sandbox key returns 401. There is nothing to leak.

## Run

```sh
./scripts/up.sh            # one command, from cold: builds (only when not built
                           # today), fresh per-session proxy in the background,
                           # foreground omp in your cwd
./scripts/up.sh bash       # plain shell instead
WORKSPACE=~/project ./scripts/up.sh
```

`/workspace` mounts the enclosing git repo of the directory you invoked
from (your plain cwd if not inside any repo), so the agent always sees
the whole project regardless of how deep you were. `WORKSPACE` overrides
for unusual cases (e.g. a non-repo directory).

The script discovers the session proxy's address via `docker inspect` and
maps `openrouter.ai` there with `--add-host` on the sandbox's `docker run`. Exiting the sandbox (or Ctrl-C) stops
both containers via a trap -- no credential-bearing process outlives a
session, and no sandbox can point at a stale proxy address.

Cert rotation is absorbed by the daily staleness rebuild; same-day rotation
needs `docker image rm omp-sandbox` (buildkit never busts its cache on
build-secret contents).

## Verified

- `omp -p ...` inside the sandbox answers through the proxy (real key never
  present).
- `Authorization: Bearer bogus` through the proxy → 200 (overwrite works).
- Direct to the real endpoint with the sandbox's key → 401.
