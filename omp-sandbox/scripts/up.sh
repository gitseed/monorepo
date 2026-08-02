#!/bin/bash
#   omp-sandbox/scripts/up.sh        # interactive omp
#   omp-sandbox/scripts/up.sh bash   # plain shell instead
#
# /workspace always mounts the monorepo root, regardless of cwd.
set -euo pipefail

GIT_PROJECT_DIR=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$GIT_PROJECT_DIR"

COMPOSE=(docker compose -f omp-sandbox/compose.yml)
PROJECT=omp-sandbox-$$
export GIT_PROJECT_DIR

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

# The daily from-scratch rebuild is also how cert rotation gets picked up:
# buildkit never cache-busts on build-secret contents.
today=$(date +%Y-%m-%d)
built_today() {
    # Date-prefix match: .Created's nanoseconds defeat jq and bsd date both.
    [[ $(docker image inspect "$1" 2>/dev/null \
        | jq -r '(.[0].Created // empty)[0:10]') == "$today" ]]
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

# The run must also be under infisical: compose diffs the full service
# config between invocations and would recreate the proxy with an empty env.
if [[ -t 0 && -t 1 ]]; then
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" run --rm sandbox "$@"
else
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" run --rm -T sandbox "$@"
fi
