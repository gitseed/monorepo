# pi-sandbox

A [pi](https://github.com/earendil-works/pi) coding agent sandboxed in [orbstack](https://orbstack.dev/) with credentials injected via [envoy](https://www.envoyproxy.io/) to prevent the agent from being able to potentially leak them.

## Memory

Every turn (user prompt, steering injection, thinking block, model reply) is
logged by the `memory` pi extension to a long-lived postgres
(`memory.compose.yml`). Sandboxes reach postgres **only** over its unix
socket, shared via the `pi-memory-socket` volume mounted at
`/var/run/postgresql` — they share no network with it. For troubleshooting
from the host: `psql -h 127.0.0.1 -U pi memory` (port published on loopback
only). Schema: `memory/init.sql`.
