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

    # Docker compose reads the pkl-rendered config from a process substitution
    # so no generated file is left on disk (like envoy.pkl in the container build).
    # Exported so infisical-spawned bash subshells can call it.
    compose() { docker compose -f <(pkl eval --format yaml sandbox/compose.pkl) "$@"; }
    export -f compose

    PROJECT=sandbox-$$
    export GIT_PROJECT_DIR
    MEMORY_COMPOSE=(docker compose -f sandbox/memory.compose.yml)
    # No secrets needed: postgres is socket-only with trust auth, shared with
    # sandbox sessions via the omp-memory-socket volume.
    echo "starting agent memory service..."
    "${MEMORY_COMPOSE[@]}" up -d --wait

    cleanup() {
        local status=$?
        if ! compose -p "$PROJECT" down --timeout 3 2>&1; then
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
    built_recently() {
        local max_age=$(( 12 * 3600 ))
        local created
        if ! created=$(docker image inspect --format '{{.Created}}' "$1" 2>/dev/null); then
            return 1
        fi
        # Docker emits timestamps like 2026-08-06T00:03:08.922498832-05:00.
        # jq 1.7.1's fromdateiso8601 requires a literal Z suffix and rejects
        # fractional seconds and timezone offsets, so strip both and append Z.
        local created_epoch now_epoch
        created_epoch=$(jq -n --arg ts "$created" '
            $ts | sub("\\.\\d+"; "")
                | sub("([+-]\\d{2}:\\d{2})$"; "")
                | . + "Z"
                | fromdateiso8601 | floor
        ')
        now_epoch=$(date +%s)
        local age=$(( now_epoch - created_epoch ))
        (( age >= 0 && age < max_age ))
    }

    if built_recently credentials-proxy; then
        compose -p "$PROJECT" build proxy
    else
        compose -p "$PROJECT" build --pull --no-cache proxy
    fi

    if built_recently sandbox; then
        infisical run -- bash -c 'compose "$@"' _ -p "$PROJECT" build sandbox
    else
        infisical run -- bash -c 'compose "$@"' _ -p "$PROJECT" build --pull --no-cache sandbox
    fi

    echo "starting credentials proxy..."
    infisical run -- bash -c 'compose "$@"' _ -p "$PROJECT" up -d --wait proxy

    if [[ $# -eq 0 ]]; then
        set -- omp
    fi

    # The run must also be under infisical so envs are populated
    if [[ -t 0 && -t 1 ]]; then
        infisical run -- bash -c 'compose "$@"' _ -p "$PROJECT" run --rm sandbox "$@"
    else
        infisical run -- bash -c 'compose "$@"' _ -p "$PROJECT" run --rm -T sandbox "$@"
    fi
}

main "$@"
