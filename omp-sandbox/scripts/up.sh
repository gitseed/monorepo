#!/bin/bash
# Build, start a per-session proxy, and drop into omp in the sandbox:
#
#   omp-sandbox/scripts/up.sh        # interactive omp
#   omp-sandbox/scripts/up.sh bash   # plain shell instead
#
# /workspace always mounts the monorepo root, regardless of cwd.
set -euo pipefail

# The repo root, anchored to this script's location.
GIT_PROJECT_DIR=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$GIT_PROJECT_DIR"

COMPOSE=(docker compose -f omp-sandbox/compose.yml)
PROJECT=omp-sandbox-$$
export GIT_PROJECT_DIR

cleanup() {
    local status=$?
    # Reap everything this session owns by label. A failure here means a
    # credential-bearing proxy may still be running -- never silent.
    if ! "${COMPOSE[@]}" -p "$PROJECT" down --timeout 3 2>&1; then
        echo "WARNING: compose down failed -- the session proxy may still" >&2
        echo "         be running with injected credentials. Reap by label:" >&2
        echo "         docker ps -q --filter label=com.docker.compose.project=$PROJECT | xargs -r docker rm -f" >&2
        status=1
    fi
    return $status
}
trap cleanup EXIT

# Always build (the layer cache makes it nearly free); rebuild from
# scratch daily, which doubles as the cert-rotation pickup (buildkit
# never cache-busts on build-secret contents).
today=$(date +%Y-%m-%d)
built_today() {
    # Date-prefix match: .Created's nanosecond timestamp defeats both jq
    # and bsd date.
    [[ $(docker image inspect "$1" 2>/dev/null \
        | jq -r '(.[0].Created // empty)[0:10]') == "$today" ]]
}

if built_today credentials-proxy; then
    "${COMPOSE[@]}" -p "$PROJECT" build proxy
else
    "${COMPOSE[@]}" -p "$PROJECT" build --pull --no-cache proxy
fi

# The sandbox build consumes the CA via a buildkit secret.
if built_today omp-sandbox; then
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" build sandbox
else
    infisical run -- \
        "${COMPOSE[@]}" -p "$PROJECT" build --pull --no-cache sandbox
fi

echo "starting credentials proxy..."
# --wait blocks until the healthcheck passes.
infisical run -- \
    "${COMPOSE[@]}" -p "$PROJECT" up -d --wait proxy

if [[ $# -eq 0 ]]; then
    set -- omp  # default command: interactive omp
fi

# -it only when a TTY exists. The run must also be under infisical:
# compose diffs the full service config between invocations and would
# recreate the proxy with an empty env otherwise.
if [[ -t 0 && -t 1 ]]; then
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" run --rm sandbox "$@"
else
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" run --rm -T sandbox "$@"
fi
