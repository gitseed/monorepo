# omp-sandbox

An [oh-my-pi](https://omp.sh/) sandboxed in [orbstack](https://orbstack.dev/) with credentials injected via [envoy](https://www.envoyproxy.io/) to prevent the agent from being able to potentially leak them.

Agent memory persists across sessions via a [Hindsight](https://github.com/vectorize-io/hindsight) service in a stable compose project (`hindsight.compose.yml`); the per-session project only shares its network. The memory bank is a persistent injection surface: any sandboxed process can write it, and recalled memories steer future sessions. Treat recalled memory as heuristic and verify against the repo before acting on it. The memory service is reference-counted: the last sandbox to exit stops it (volume preserved), so a new session brings memory back with history intact.
