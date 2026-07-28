#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'agent-sandbox: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

for command_name in container curl git nc openssl tofu; do
  require_command "$command_name"
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd -- "$script_dir/.." && pwd)"
repo_root="$(git -C "$project_dir" rev-parse --show-toplevel)"
secrets_tofu_dir="$repo_root/agent-secrets/tofu"

dns_server="${AGENT_SANDBOX_DNS:-203.0.113.113}"
vault_name="agent-sandbox"
vault_image="agent-sandbox-vault:0.39.0"
agent_image="agent-sandbox-agent:17.1.6"

tofu_output() {
  local output_name="$1"
  (
    cd "$secrets_tofu_dir"
    TF_WORKSPACE=global tofu output -raw "$output_name"
  )
}

if ! infisical_project_id="$(tofu_output agent_vault_project_id)"; then
  die "agent-secrets is not ready; run TF_WORKSPACE=global tofu apply in $secrets_tofu_dir"
fi
if ! infisical_client_id="$(tofu_output agent_vault_client_id)"; then
  die "agent-secrets is not ready; run TF_WORKSPACE=global tofu apply in $secrets_tofu_dir"
fi
if ! infisical_client_secret="$(tofu_output agent_vault_client_secret)"; then
  die "agent-secrets is not ready; run TF_WORKSPACE=global tofu apply in $secrets_tofu_dir"
fi

[[ -n "$infisical_project_id" ]] || die "agent_vault_project_id is empty"
[[ -n "$infisical_client_id" ]] || die "agent_vault_client_id is empty"
[[ -n "$infisical_client_secret" ]] || die "agent_vault_client_secret is empty"

if ! container system status >/dev/null 2>&1; then
  container system start
fi

build_image() {
  local target="$1"
  local tag="$2"
  local -a cache_args=()

  if ! container image inspect "$tag" >/dev/null 2>&1; then
    cache_args+=(--no-cache)
  fi

  container build \
    --pull \
    "${cache_args[@]}" \
    --target "$target" \
    --tag "$tag" \
    --dns "$dns_server" \
    --file "$project_dir/Containerfile" \
    "$project_dir"
}

printf 'Building Agent Vault image...\n'
build_image vault "$vault_image"
printf 'Building Oh My Pi image...\n'
build_image agent "$agent_image"

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

export INFISICAL_URL="https://app.infisical.com"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_ID="$infisical_client_id"
export INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET="$infisical_client_secret"
unset infisical_client_id infisical_client_secret

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
  --env INFISICAL_URL \
  --env INFISICAL_UNIVERSAL_AUTH_CLIENT_ID \
  --env INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET \
  --env AGENT_VAULT_TELEMETRY=false \
  "$vault_image" \
  server \
  --host 0.0.0.0 \
  --port "$api_port" \
  --mitm-port "$proxy_port" \
  >/dev/null
vault_started=1

unset INFISICAL_URL
unset INFISICAL_UNIVERSAL_AUTH_CLIENT_ID
unset INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET

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
  --credential-store infisical \
  --infisical-project-id "$infisical_project_id" \
  --infisical-environment global \
  --infisical-path / \
  --poll-interval-seconds 60 \
  >/dev/null
unset infisical_project_id

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
