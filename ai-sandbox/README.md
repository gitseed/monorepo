# ai-sandbox

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (dsh) sandboxed in [orbstack](https://orbstack.dev/) with credentials injected via [envoy](https://www.envoyproxy.io/) to prevent the agent from being able to potentially leak them.

```console
$ ai-sandbox/scripts/up.bash        # DeepSeek Harness Web UI on http://127.0.0.1:3080
$ ai-sandbox/scripts/up.bash bash   # plain shell instead
```

Model routing: `container/dsh/settings.yaml` mounts the pi-ai adapter's OpenRouter route (`apiKeyEnv: OPENROUTER_API_KEY` — the dummy env var the credentials proxy replaces mid-flight), and `container/dsh/cordis.patch.yml` points the deployment default model at `qwen/qwen3.8-max`. The settings document is hot-reloaded from `$DSH_HOME/settings.yaml`; the profile patch layer is baked into the image.

The Web UI binds the container's own address at launch — dsh refuses `--host 0.0.0.0` outright ("would expose remote code execution to the network") — and the compose service publishes host loopback onto it, with `--trusted-host 127.0.0.1:3080` whitelisted for the browser-trust fence.

Trust posture: `DSH_PERMISSION_MODE=danger-full-access` (the container is already the confinement boundary; dsh's default ask-approval policy would stall an unattended session) and `DSH_TELEMETRY_DISABLED=1` (telemetry is default-off upstream; this pins it).

dsh is in developer preview and pinned in `container/dsh/host-package.json`; upstream promises compatibility-breaking changes, so re-baseline deliberately. The runtime is pinned Deno: dsh's engines nominally name Node, but Deno 2.9.5 probes clean on everything dsh imports (`node:module.stripTypeScriptTypes`, `node:vm`, `node:sqlite`, `worker_threads`), and bun — which this image used to run — is out entirely (even the latest 1.3.14 lacks `stripTypeScriptTypes`, so dsh's plugin tree never loads). dsh is installed as a local npm project under `/opt/dsh` because its node-pty Node-API addon only loads from a local `node_modules`; the `dsh` wrapper grants `--allow-all` and feeds the proxy CA to deno's TLS stack. If deno trips end-to-end, the documented fallback is the pinned Node ≥22.19 tarball.

The previous occupant was [oh-my-pi](https://omp.sh/) with custom extensions (`memory`, `morph`, `openrouter-advisor`) and RTK; those live in git history as the reference for porting them to Cordis plugins. RTK's bash-output compression is already covered by dsh's native spill policy and tool-result pruner. The memory extension's postgres volume (`omp-memory_pgdata`) is untouched by the cutover; drop it when the memory plugin is ported, or keep it to preserve the data.
