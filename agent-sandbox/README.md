# Agent Sandbox

An ephemeral Oh My Pi container with this monorepo mounted at `/workspace`.
OpenRouter requests go through a separate, equally ephemeral Agent Vault
container. Oh My Pi receives a placeholder API key; Agent Vault replaces it
with `OPENROUTER_API_KEY` only for requests to `openrouter.ai/api/*`.

Ordinary internet access is unchanged. Closing the terminal or tmux pane stops
and removes both containers.

At startup, the trusted host authenticates to Infisical with the existing AWS
IAM machine identity and runs `infisical export` for `agent-secrets`. The
result is piped into Agent Vault's built-in store without creating a secrets
file. This is a startup snapshot: secret changes take effect the next time the
sandbox starts.

## Prerequisites

The host needs the Infisical CLI, working AWS credentials, and
`INFISICAL_MACHINE_IDENTITY_ID`. The checked-in
`agent-secrets/.infisical.json` binds exports to the `agent` project and its
`global` environment.

This uses the existing Apple container DNS setup from the Lightning agent. If
that host mapping has not already been created:

```bash
sudo container system dns create host.container.internal --localhost 203.0.113.113
```

## Run

From anywhere inside this monorepo:

```bash
./agent-sandbox/scripts/ai.bash
```

The default model matches the Lightning agent:
`openrouter/deepseek/deepseek-v4-flash`. Override it for one run with:

```bash
OMP_MODEL=openrouter/anthropic/claude-sonnet-4.5 \
  ./agent-sandbox/scripts/ai.bash
```

`services.yaml` is baked into the Agent Vault image. Add another proxied
service there and launch the script again to rebuild and apply it.

The Agent Vault database, cached secrets, generated CA, owner account, and
agent token live only for the lifetime of that invocation. Oh My Pi's own
session data is also ephemeral; changes inside `/workspace` persist because
that is the bind-mounted monorepo.
