# sandbox

An [oh-my-pi](https://omp.sh/) sandboxed in [orbstack](https://orbstack.dev/) with credentials injected via [envoy](https://www.envoyproxy.io/) to prevent the agent from being able to potentially leak them.

Memory: omp's built-in memory tools are off (`memory.backend: "off"`). A custom extension (`container/extensions/memory.ts`) captures every heard/said/thought memory to the `omp-memory` postgres (pgvector) container over its unix socket, and registers four tools: `recollect` (embedding-similarity search over other sessions; returns id/date/length/summary), `recall` (full text by id), `remember` (explicitly save; returns id), and `suppress` (hide from recollect). Configured by `container/memory.json` (models, limits, postgres connection); currently disabled — set `"enabled": true` there to turn it on. Postgres also listens on host loopback for troubleshooting: `psql -h 127.0.0.1 -U omp memory`.

Note: `init.sql` only runs on a fresh data volume. If an `omp-memory_pgdata` volume exists from the phase-1 `turns` schema, drop it (`docker compose -f sandbox/memory.compose.yml down -v`) so the `memories` schema initializes.
