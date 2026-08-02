#!/bin/bash
# The whole sandbox boundary in one command:
#
#   omp-sandbox/scripts/up.sh      # build if stale, session proxy, interactive omp
#   omp-sandbox/scripts/up.sh bash # a plain shell instead of omp
#
# The sandbox works on THIS monorepo: /workspace always mounts the whole
# repo root (compose.yml's relative bind), and the build contexts live
# there too. Invocation cwd is irrelevant.
#
# Topology and container plumbing live in omp-sandbox/compose.yml
# (services, network, healthcheck, extra_hosts). What stays here is what
# compose can't express:
#   - daily-staleness rebuilds (cert-rotation absorption; secret mounts
#     never bust the build cache, so same-day builds must not be
#     trusted after a rotation -- wait a day or rm the image)
#   - infisical: `infisical run -- docker compose ...` injects the
#     secrets into compose's own env, which passes them into builds and
#     the proxy container without touching disk
#   - cleanup: per-session compose projects (omp-sandbox-$$) let
#     `compose down` reap everything this session owns by label
set -euo pipefail

# GIT_PROJECT_DIR: the single repo that defines both the tooling (build
# contexts are relative to it) and the agent's work (mounted at
# /workspace). Anchored to this script's location, not the caller's cwd.
GIT_PROJECT_DIR=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$GIT_PROJECT_DIR"

COMPOSE=(docker compose -f omp-sandbox/compose.yml)
PROJECT=omp-sandbox-$$
export GIT_PROJECT_DIR

cleanup() {
    local status=$?
    # compose down reaps by label: sandbox, proxy, anything else the
    # project created. A --rm `compose run` usually already took the
    # sandbox; that is fine. What must never pass silently: failure here
    # means a credential-bearing proxy container may still be alive.
    if ! "${COMPOSE[@]}" -p "$PROJECT" down --timeout 3 2>&1; then
        echo "WARNING: compose down failed -- the session proxy may still" >&2
        echo "         be running with injected credentials. Reap by label:" >&2
        echo "         docker ps -q --filter label=com.docker.compose.project=$PROJECT | xargs -r docker rm -f" >&2
        status=1
    fi
    return $status
}
trap cleanup EXIT

stale() {
    # true when the image is missing, was not built today, or is older
    # than any file in its build context. Daily granularity misses the
    # classic footgun: build in the morning, merge a config change at
    # noon — an AAAA-ipv4-calendared check says "fresh" while baked
    # envoy.yaml no longer matches the repo.
    local name="$1" context="$2" created epoch newest
    created=$(docker image inspect "$name" 2>/dev/null \
        | jq -r '(.[0].Created // empty)')
    [[ -z $created || ${created:0:10} != "$(date +%Y-%m-%d)" ]] && return 0
    # docker emits nanoseconds + a colonated TZ offset; bsd date's %z
    # wants neither, so normalize before the round-trip.
    epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S%z' \
        "$(printf '%s' "$created" | sed -E 's/\.[0-9]+//' -e 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')" \
        +%s 2>/dev/null || echo 0)
    newest=$(find "$context" -type f -not -name '.*' -exec stat -f %m {} + | sort -n | tail -1)
    [[ -n $newest && $newest -gt "$epoch" ]]
}

if stale credentials-proxy omp-sandbox/container; then
    echo "building credentials-proxy (stale)..."
    "${COMPOSE[@]}" -p "$PROJECT" build --pull --no-cache proxy
fi

if stale omp-sandbox omp-sandbox/container; then
    echo "building omp-sandbox (stale)..."
    infisical run -- \
        "${COMPOSE[@]}" -p "$PROJECT" build --pull --no-cache sandbox
fi

echo "starting credentials proxy..."
# --wait blocks until the healthcheck passes (envoy accepting :443).
infisical run -- \
    "${COMPOSE[@]}" -p "$PROJECT" up -d --wait proxy

if [[ $# -eq 0 ]]; then
    set -- omp  # default command: interactive omp
fi

# -it only when a TTY exists (macOS harnesses and CI often lack one).
# Note: compose compares the full service config (incl. the infisical-
# injected env) between invocations — the run MUST also be under
# infisical, else it recreates the proxy with an empty env mid-session.
if [[ -t 0 && -t 1 ]]; then
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" run --rm sandbox "$@"
else
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" run --rm -T sandbox "$@"
fi
