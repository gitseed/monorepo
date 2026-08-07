#!/bin/bash
# sandbox/scripts/up.sh      # interactive omp
# sandbox/scripts/up.sh bash # plain shell instead
set -euo pipefail

# Everything lives inside main() so bash parses the whole file before running
# any of it. Bash otherwise reads scripts lazily by byte offset, and editing
# this file while a sandbox session is running causes bogus syntax errors when
# the session exits.
main() {
    # omp workspace is the monorepo root directory
    GIT_PROJECT_DIR=$(cd -- "$(dirname -- "$0")/../.." && pwd)
    cd "$GIT_PROJECT_DIR"

    COMPOSE=(docker compose -f sandbox/compose.yml)
    PROJECT=sandbox-$$
    export GIT_PROJECT_DIR
    MEMORY_COMPOSE=(docker compose -f sandbox/memory.compose.yml)
    # No secrets needed: postgres is socket-only with trust auth, shared with
    # sandbox sessions via the omp-memory-socket volume.
    echo "starting agent memory service..."
    "${MEMORY_COMPOSE[@]}" up -d --wait

    cleanup() {
        local status=$?
        if ! "${COMPOSE[@]}" -p "$PROJECT" down --timeout 3 2>&1; then
            echo "WARNING: compose down failed -- the session proxy may still" >&2
            echo "         be running with injected credentials. Reap by label:" >&2
            echo "         docker ps -q --filter label=com.docker.compose.project=$PROJECT | xargs -r docker rm -f" >&2
            status=1
        fi

        # Stop the shared memory service when the last sandbox exits.
        local projects
        if ! projects=$(docker ps --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null); then
            echo "WARNING: could not enumerate containers; leaving memory service running" >&2
            return $status
        fi
        if printf '%s\n' "$projects" | grep -q '^sandbox-[0-9][0-9]*$'; then
            return $status   # another session is still active
        fi
        "${MEMORY_COMPOSE[@]}" down --timeout 10 2>/dev/null || true
        return $status
    }
    trap cleanup EXIT

    # Rebuild at least every 12 hours to update harness version.
    cutoff=$(date -d '12 hours ago' -u +%s 2>/dev/null || date -v-12H -u +%s)
    built_recently() {
        local created
        created=$(docker image inspect "$1" 2>/dev/null \
            | jq -r '(.[0].Created // empty)[0:19]') || return 1
        [[ -z "$created" ]] && return 1
        local epoch
        epoch=$(date -d "$created" -u +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%S' "$created" -u +%s) || return 1
        (( epoch > cutoff ))
    }

    if built_recently credentials-proxy; then
        "${COMPOSE[@]}" -p "$PROJECT" build proxy
    else
        "${COMPOSE[@]}" -p "$PROJECT" build --pull --no-cache proxy
    fi

    if built_recently sandbox; then
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
}

main "$@"
