# ai-sandbox

An [oh-my-pi](https://omp.sh/) sandboxed in [orbstack](https://orbstack.dev/) with credentials injected via [envoy](https://www.envoyproxy.io/) to prevent the agent from being able to potentially leak them.

Memory: omp's built-in memory tools are off (`memory.backend: "off"`). A custom extension (`container/extensions/memory.ts`) captures every heard/said/thought memory to the `omp-memory` postgres (pgvector) container over its unix socket, and registers four tools: `recollect` (embedding-similarity search over other sessions; returns id/date/length/summary), `recall` (full text by id), `remember` (explicitly save; returns id), and `suppress` (hide from recollect). Configured by `container/extensions/memory/memory.json` (models, limits, postgres connection); currently disabled — set `"enabled": true` there to turn it on. Postgres also listens on host loopback for troubleshooting: `psql -h 127.0.0.1 -U omp memory`.

Note: `init.sql` only runs on a fresh data volume. If an `omp-memory_pgdata` volume exists from the phase-1 `turns` schema, drop it (`docker compose -f ai-sandbox/memory.compose.yml down -v`) so the `memories` schema initializes.

## DeepSeek Harness spike

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (dsh) is DeepSeek's developer-preview agent harness — "everything is a plugin" on the [Cordis](https://github.com/cordiverse/cordis) kernel. The spike boots its Web UI inside this sandbox's trust envelope to validate the port before any plugin work:

```console
$ ai-sandbox/scripts/up.bash dsh        # then open http://127.0.0.1:3080
$ ai-sandbox/scripts/up.bash dsh bash   # debug shell in the dsh container
```

The `dsh-sandbox` image builds `FROM ai-sandbox` and reuses all of its plumbing: dummy env vars overwritten by the [envoy](https://www.envoyproxy.io/) credentials proxy, proxy container links, dnsmasq, CA trust, and the git-signing entrypoint. The model route is OpenRouter (`container/dsh/settings.yaml` mounts the pi-ai adapter's `openrouter` route; `container/dsh/cordis.patch.yml` points the default model at `qwen/qwen3.8-max`), so the first session already exercises the proxy path end to end.

What the spike proves: dsh boots on this image's bun runtime (its `node` shebang lands on the bun symlink — intentional, and unverified upstream), the Web UI is reachable from the host (dsh refuses `--host 0.0.0.0`, so the service binds the container's own address and publishes host loopback), and the proxy injects the real key for model calls.

Trust posture: `DSH_PERMISSION_MODE=danger-full-access` (the container is already the confinement boundary; dsh's default ask-approval would stall an unattended session) and `DSH_TELEMETRY_DISABLED=1` (telemetry is default-off upstream; this pins it).

Not ported yet: the custom extensions (`memory`, `morph`, `openrouter-advisor`), the RTK bash-output compression (dsh ships native spill/tool-result pruning), the context7 MCP server, and firecrawl web search (dsh ships exa/perplexity/deepseek providers). The harness version is pinned in `container/dsh-sandbox.containerfile`; upstream promises compatibility-breaking changes, so re-baseline deliberately.
