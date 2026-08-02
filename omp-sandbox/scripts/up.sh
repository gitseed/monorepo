#!/bin/bash
# The whole sandbox boundary in one command:
#
#   omp-sandbox/scripts/up.sh                  # build if stale, session proxy, interactive omp
#   WORKSPACE=~/proj omp-sandbox/scripts/up.sh # different directory mounted at /workspace
#   omp-sandbox/scripts/up.sh bash             # a plain shell instead of omp
#
# The default /workspace mount is the caller's ENCLOSING GIT REPO root
# (falling back to the plain cwd when not inside any repo) -- a sandbox
# always sees the whole project, not just the subdirectory it was
# invoked from.
#
# Builds: each image is rebuilt only if it was NOT built today. This doubles
# as the cert-rotation path: a tofu-applied rotation is picked up by the next
# run (secret mounts never bust the build cache, so same-day builds must not
# be trusted after a rotation -- just wait a day or rm the image).
#
# Lifecycle: the credentials proxy is launched per session in the background
# and both containers are torn down on exit. Nothing credential-bearing
# outlives a session, and no sandbox can ever point at a stale proxy address.
set -euo pipefail

# Must be resolved BEFORE cd-ing to the monorepo below: /workspace
# mounts the caller's repo, wherever this script was invoked from.
if [[ -z ${WORKSPACE:-} ]]; then
    WORKSPACE=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
fi

# Build contexts are relative; anchor them to this script's repo so the
# script works from ANY caller cwd (the sandbox is for working on
# external repos too, not just the monorepo).
ROOT=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"

NETWORK=agent
PROXY_NAME=credentials-proxy-$$
SANDBOX_NAME=omp-sandbox-$$

cleanup() {
    local status=$?
    # --rm containers are usually already gone at this point, which is fine
    # and silent. What must never pass silently: a container that is still
    # alive and cannot be stopped -- in particular the proxy, which holds
    # injected credentials for as long as it runs.
    local name
    for name in "$SANDBOX_NAME" "$PROXY_NAME"; do
        docker inspect "$name" >/dev/null 2>&1 || continue
        if ! docker stop "$name" >/dev/null 2>&1; then
            echo "WARNING: could not stop $name -- it may still be running." >&2
            echo "         stop it manually: docker rm -f $name" >&2
            status=1
        fi
    done
    return $status
}
trap cleanup EXIT

docker network inspect "$NETWORK" >/dev/null 2>&1 \
    || docker network create "$NETWORK" >/dev/null

stale() {
    # true when the image is missing or was not built today (UTC)
    local created
    created=$(docker image inspect "$1" 2>/dev/null \
        | jq -r '.[0].Created // empty')
    [[ ${created:0:10} != "$(date -u +%Y-%m-%d)" ]]
}

if stale credentials-proxy; then
    echo "building credentials-proxy (not built today)..."
    docker build --pull --no-cache \
        --tag credentials-proxy \
        --file credentials-proxy/container/main.containerfile \
        credentials-proxy/container/
fi

if stale omp-sandbox; then
    echo "building omp-sandbox (not built today)..."
    infisical run -- \
        docker build --pull --no-cache \
            --tag omp-sandbox \
            --secret id=ca_cert,env=CREDENTIALS_PROXY_CA_CERT \
            --file omp-sandbox/container/main.containerfile \
            omp-sandbox/container/
fi

echo "starting credentials proxy..."
infisical run -- \
    docker run --rm -d \
        --name "$PROXY_NAME" \
        --network "$NETWORK" \
        --env OPENROUTER_API_KEY \
        --env CREDENTIALS_PROXY_SERVER_CERT \
        --env CREDENTIALS_PROXY_SERVER_KEY \
        credentials-proxy >/dev/null

PROXY_IP=
deadline=$((SECONDS + 20))
until [[ $(docker inspect "$PROXY_NAME" 2>/dev/null \
            | jq -r '.[0].State.Status // empty') == running ]] \
        && PROXY_IP=$(docker inspect "$PROXY_NAME" 2>/dev/null \
            | jq -r --arg net "$NETWORK" '.[0].NetworkSettings.Networks[$net].IPAddress // empty') \
        && [[ -n $PROXY_IP ]] \
        && nc -z "$PROXY_IP" 443 2>/dev/null; do
    if (( SECONDS >= deadline )); then
        echo "credentials-proxy failed to come up; logs:" >&2
        docker logs "$PROXY_NAME" 2>&1 | tail -20 >&2
        exit 1
    fi
    sleep 0.5
done

if [[ $# -eq 0 ]]; then
    set -- omp  # default command: interactive omp
fi

docker run --rm -it \
    --name "$SANDBOX_NAME" \
    --network "$NETWORK" \
    --add-host "openrouter.ai:$PROXY_IP" \
    --volume "$WORKSPACE:/workspace" \
    --workdir /workspace \
    omp-sandbox "$@"
