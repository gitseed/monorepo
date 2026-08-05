# sandbox

An [oh-my-pi](https://omp.sh/) sandboxed in [orbstack](https://orbstack.dev/) with credentials injected via [envoy](https://www.envoyproxy.io/) to prevent the agent from being able to potentially leak them.

Memory: omp's built-in memory tools are off (`memory.backend: "off"`). A custom turn-logging extension (`container/extensions/memory.ts`) writes every say/steer/think/reply turn to the `omp-memory` postgres container over its unix socket — currently disabled; set `MEMORY_ENABLED=1` on the sandbox service in `compose.yml` to turn it on. Postgres also listens on host loopback for troubleshooting: `psql -h 127.0.0.1 -U omp memory`.
