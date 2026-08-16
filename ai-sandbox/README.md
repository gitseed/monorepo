# ai-sandbox

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (dsh) sandboxed in [orbstack](https://orbstack.dev/) with credentials injected via [envoy](https://www.envoyproxy.io/) to prevent the agent from being able to potentially leak them.

```console
$ ai-sandbox/scripts/up.bash        # DeepSeek Harness Web UI on http://127.0.0.1:3080
$ ai-sandbox/scripts/up.bash bash   # plain shell instead
```

Model routing: `container/dsh/settings.yaml` mounts the pi-ai adapter's OpenRouter route (`apiKeyEnv: OPENROUTER_API_KEY` — the dummy env var the credentials proxy replaces mid-flight), and `container/dsh/cordis.patch.yml` points the deployment default model at `qwen/qwen3.8-max`. The settings document is hot-reloaded from `$DSH_HOME/settings.yaml`; the profile patch layer is baked into the image.

The Web UI binds the container's own address at launch — dsh refuses `--host 0.0.0.0` outright ("would expose remote code execution to the network") — and the compose service publishes host loopback onto it, with `--trusted-host 127.0.0.1:3080` whitelisted for the browser-trust fence.

Trust posture: `DSH_PERMISSION_MODE=danger-full-access` (the container is already the confinement boundary; dsh's default ask-approval policy would stall an unattended session) and `DSH_TELEMETRY_DISABLED=1` (telemetry is default-off upstream; this pins it).

dsh is in developer preview and pinned in `container/ai-sandbox.containerfile`; upstream promises compatibility-breaking changes, so re-baseline deliberately. The runtime is pinned Node LTS: dsh's engines require `^22.19.0 || >=24.0.0`, and both alternatives fail — bun has no `node:module.stripTypeScriptTypes` (verified absent in the latest release and in master's source, so dsh's plugin tree never loads), and deno 2.9.5 deadlocks mid npm install ([denoland/deno#36599](https://github.com/denoland/deno/issues/36599)).

The previous occupant was [oh-my-pi](https://omp.sh/) with custom extensions (`memory`, `morph`, `openrouter-advisor`) and RTK; those live in git history as the reference for porting them to Cordis plugins. RTK's bash-output compression is already covered by dsh's native spill policy and tool-result pruner. The memory extension's postgres volume (`omp-memory_pgdata`) is untouched by the cutover; drop it when the memory plugin is ported, or keep it to preserve the data.
