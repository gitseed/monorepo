#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'agent-sandbox: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

for command_name in container curl git infisical jq nc openssl; do
  require_command "$command_name"
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"
repo_root="$(git -C "$project_dir" rev-parse --show-toplevel)"
agent_secrets_dir="$repo_root/agent-secrets"
infisical_config="$agent_secrets_dir/.infisical.json"

dns_server="${AGENT_SANDBOX_DNS:-203.0.113.113}"
vault_name="agent-sandbox"
vault_image="agent-sandbox-vault:0.39.0"
agent_image="agent-sandbox-agent:17.1.6"
[[ -n "${INFISICAL_MACHINE_IDENTITY_ID:-}" ]] \
  || die "INFISICAL_MACHINE_IDENTITY_ID is required for Infisical AWS IAM login"
if ! infisical_project_id="$(
  jq -er \
    '.workspaceId | select(type == "string" and length > 0)' \
    "$infisical_config"
)"; then
  die "workspaceId is missing from $infisical_config"
fi

printf 'Exporting agent secrets from Infisical...\n'
if ! infisical_access_token="$(
  cd "$project_dir"
  infisical login \
    --domain https://app.infisical.com \
    --method aws-iam \
    --plain \
    --silent
)"; then
  die "Infisical AWS IAM login failed"
fi
[[ -n "$infisical_access_token" ]] || die "Infisical returned an empty access token"

if ! agent_secrets_json="$(
  cd "$agent_secrets_dir"
  INFISICAL_UNIVERSAL_AUTH_ACCESS_TOKEN="$infisical_access_token" \
    infisical export \
      --domain https://app.infisical.com \
      --format json \
      --projectId "$infisical_project_id" \
      --silent
)"; then
  unset infisical_access_token
  die "could not export agent-secrets from Infisical"
fi
unset infisical_access_token infisical_project_id
[[ -n "$agent_secrets_json" ]] || die "Infisical exported no agent secrets"

if ! container system status >/dev/null 2>&1; then
  container system start
fi

build_image() {
  local containerfile="$1"
  local tag="$2"
  local -a cache_args=()

  if ! container image inspect "$tag" >/dev/null 2>&1; then
    cache_args+=(--no-cache)
  fi

  container build \
    --pull \
    "${cache_args[@]}" \
    --tag "$tag" \
    --dns "$dns_server" \
    --file "$project_dir/$containerfile" \
    "$project_dir"
}

printf 'Building Agent Vault image...\n'
build_image vault.containerfile "$vault_image"
printf 'Building Oh My Pi image...\n'
build_image agent.containerfile "$agent_image"

choose_ports() {
  local attempt
  local candidate

  for ((attempt = 0; attempt < 100; attempt++)); do
    candidate=$((20000 + ((RANDOM + $$ + attempt) % 14000) * 2))
    if ! nc -z 127.0.0.1 "$candidate" >/dev/null 2>&1 \
      && ! nc -z 127.0.0.1 "$((candidate + 1))" >/dev/null 2>&1; then
      api_port="$candidate"
      proxy_port="$((candidate + 1))"
      return
    fi
  done

  die "could not find two free localhost ports"
}

choose_ports

run_id="$$-$RANDOM"
vault_container="agent-sandbox-vault-$run_id"
agent_container="agent-sandbox-agent-$run_id"
vault_started=0
agent_started=0

cleanup() {
  local exit_code="$?"
  trap - EXIT HUP INT TERM

  if ((agent_started)); then
    container stop --time 2 "$agent_container" >/dev/null 2>&1 || true
  fi
  if ((vault_started)); then
    container stop --time 2 "$vault_container" >/dev/null 2>&1 || true
  fi

  exit "$exit_code"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Starting ephemeral Agent Vault...\n'
container run \
  --detach \
  --init \
  --read-only \
  --rm \
  --name "$vault_container" \
  --dns "$dns_server" \
  --publish "127.0.0.1:$api_port:$api_port" \
  --publish "127.0.0.1:$proxy_port:$proxy_port" \
  --tmpfs /data \
  --tmpfs /tmp \
  --env AGENT_VAULT_TELEMETRY=false \
  "$vault_image" \
  server \
  --host 0.0.0.0 \
  --port "$api_port" \
  --mitm-port "$proxy_port" \
  >/dev/null
vault_started=1

vault_ready=0
for ((attempt = 0; attempt < 100; attempt++)); do
  if curl --noproxy '*' --fail --silent "http://127.0.0.1:$api_port/health" >/dev/null; then
    vault_ready=1
    break
  fi
  sleep 0.2
done

if ((!vault_ready)); then
  container logs "$vault_container" >&2 || true
  die "Agent Vault did not become ready"
fi

bootstrap_password="$(openssl rand -hex 32)"
printf '%s\n' "$bootstrap_password" \
  | container exec --interactive "$vault_container" \
      agent-vault auth register \
      --address "http://127.0.0.1:$api_port" \
      --email "agent-sandbox@example.invalid" \
      --password-stdin \
      >/dev/null
unset bootstrap_password

container exec "$vault_container" \
  agent-vault vault create "$vault_name" \
  >/dev/null

printf '%s' "$agent_secrets_json" \
  | container exec --interactive "$vault_container" \
      import-agent-secrets "$vault_name" \
      >/dev/null
unset agent_secrets_json

container exec "$vault_container" \
  agent-vault vault service set \
  --vault "$vault_name" \
  --file /etc/agent-vault/services.yaml \
  >/dev/null

if ! agent_vault_token="$(
  container exec "$vault_container" \
    agent-vault agent create oh-my-pi \
    --vault "$vault_name:proxy" \
    --token-only
)"; then
  die "could not create the Oh My Pi proxy token"
fi
[[ -n "$agent_vault_token" ]] || die "Agent Vault returned an empty proxy token"

export AGENT_VAULT_TOKEN="$agent_vault_token"
export AGENT_VAULT_ADDR="http://host.container.internal:$api_port"
export AGENT_VAULT_VAULT="$vault_name"
export OPENROUTER_API_KEY="agent-vault-replaces-this-placeholder"
unset agent_vault_token

agent_env_args=(
  --env AGENT_VAULT_TOKEN
  --env AGENT_VAULT_ADDR
  --env AGENT_VAULT_VAULT
  --env OPENROUTER_API_KEY
)
if [[ -n "${OMP_MODEL:-}" ]]; then
  agent_env_args+=(--env OMP_MODEL)
fi

printf 'Starting Oh My Pi in %s...\n' "$repo_root"
agent_started=1
container run \
  --init \
  --rm \
  --name "$agent_container" \
  --dns "$dns_server" \
  --volume "$repo_root:/workspace" \
  --workdir /workspace \
  --interactive \
  --tty \
  "${agent_env_args[@]}" \
  "$agent_image" \
  "$@"
