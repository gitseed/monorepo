# pi-sandbox

A [pi](https://github.com/earendil-works/pi) coding agent sandboxed in [orbstack](https://orbstack.dev/) with credentials injected via [envoy](https://www.envoyproxy.io/) to prevent the agent from being able to potentially leak them.

## Memory

Every turn (user prompt, steering injection, thinking block, model reply) is
logged by the `memory` pi extension to a long-lived postgres
(`memory.compose.yml`). Postgres listens **only** on its unix socket — TCP is
disabled and the container has no network — and the socket directory is shared
with sandbox sessions via the `pi-memory-socket` volume, mounted at
`/var/run/postgresql`. Schema: `memory/init.sql`.
