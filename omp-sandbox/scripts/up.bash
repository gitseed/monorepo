#!/bin/bash
# omp-sandbox/scripts/up.sh      # interactive omp
# omp-sandbox/scripts/up.sh bash # plain shell instead
set -euo pipefail

# omp workspace is the monorepo root directory
GIT_PROJECT_DIR=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$GIT_PROJECT_DIR"

COMPOSE=(docker compose -f omp-sandbox/compose.yml)
PROJECT=omp-sandbox-$$
export GIT_PROJECT_DIR
HINDSIGHT_COMPOSE=(docker compose -f omp-sandbox/hindsight.compose.yml)
# Shared network so the per-session project can reach the stable memory service.
docker network create omp-sandbox-net 2>/dev/null || true
echo "starting agent memory service..."
infisical run -- "${HINDSIGHT_COMPOSE[@]}" up -d --wait

cleanup() {
    local status=$?
    if ! "${COMPOSE[@]}" -p "$PROJECT" down --timeout 3 2>&1; then
        echo "WARNING: compose down failed -- the session proxy may still" >&2
        echo "         be running with injected credentials. Reap by label:" >&2
        echo "         docker ps -q --filter label=com.docker.compose.project=$PROJECT | xargs -r docker rm -f" >&2
        status=1
    fi
    return $status
}
trap cleanup EXIT

# Daily rebuild to update harness version.
today=$(date +%Y-%m-%d)
built_today() {
    [[ $(docker image inspect "$1" 2>/dev/null | jq -r '(.[0].Created // empty)[0:10]') == "$today" ]]
}

if built_today credentials-proxy; then
    "${COMPOSE[@]}" -p "$PROJECT" build proxy
else
    "${COMPOSE[@]}" -p "$PROJECT" build --pull --no-cache proxy
fi

if built_today omp-sandbox; then
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" build sandbox
else
    infisical run -- \
        "${COMPOSE[@]}" -p "$PROJECT" build --pull --no-cache sandbox
fi

echo "starting credentials proxy..."
infisical run -- \
    "${COMPOSE[@]}" -p "$PROJECT" up -d --wait proxy

if [[ $# -eq 0 ]]; then
    set -- omp
fi

# The run must also be under infisical so envs are populated
if [[ -t 0 && -t 1 ]]; then
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" run --rm sandbox "$@"
else
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" run --rm -T sandbox "$@"
fi
