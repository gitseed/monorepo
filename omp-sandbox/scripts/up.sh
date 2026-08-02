#!/bin/bash
# The whole sandbox boundary in one command:
#
# omp-sandbox/scripts/up.sh      # build (cached, --no-cache daily), session proxy, interactive omp
#   omp-sandbox/scripts/up.sh bash # a plain shell instead of omp
#
# The sandbox works on THIS monorepo: /workspace always mounts the whole
# repo root (compose.yml's relative bind), and the build contexts live
# there too. Invocation cwd is irrelevant.
#
# Topology and container plumbing live in omp-sandbox/compose.yml
# (services, network, aliases, healthcheck). What stays here is what
# compose can't express:
#   - always-build (layers cache makes it nearly free), with a daily
#     --no-cache --pull for cache-reset hygiene and the cert-rotation
#     path (a tofu-applied cert rotation lands in the next day's run;
#     buildkit never busts its cache on build-secret contents)
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

# Builds are cheap with the layer cache, so always build: whatever
# changed since the last build gets picked up immediately. The only
# decision is when to trust the cache: rerun from scratch (--no-cache
# --pull) once per day, which doubles as the cert-rotation path (a
# tofu-applied rotation is picked up by the next day's run; cache
# invalidation on build-secret contents is not a thing).
today=$(date +%Y-%m-%d)
built_today() {
    # true when $1 was built today (local time -- this whole setup is
    # laptop-scheduled, not UTC-scheduled). docker's .Created carries
    # nanoseconds + a TZ offset that jq/fromdateiso8601 and bsd date
    # round-trips both choke on; the date prefix match sidesteps both.
    [[ $(docker image inspect "$1" 2>/dev/null \
        | jq -r '(.[0].Created // empty)[0:10]') == "$today" ]]
}

if built_today credentials-proxy; then
    "${COMPOSE[@]}" -p "$PROJECT" build proxy
else
    "${COMPOSE[@]}" -p "$PROJECT" build --pull --no-cache proxy
fi

# The sandbox build consumes the CA via a buildkit secret from infisical.
if built_today omp-sandbox; then
    infisical run -- "${COMPOSE[@]}" -p "$PROJECT" build sandbox
else
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
