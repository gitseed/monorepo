#!/bin/bash
# The whole sandbox boundary in one command:
#
#   omp-sandbox/up.sh                  # build if stale, session proxy, interactive omp
#   WORKSPACE=~/proj omp-sandbox/up.sh # different directory mounted at /workspace
#   omp-sandbox/up.sh bash             # a plain shell instead of omp
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

CALLER_CWD=$PWD
cd "$(dirname "$0")/.."

NETWORK=agent
PROXY_NAME=credentials-proxy-$$
SANDBOX_NAME=omp-sandbox-$$

cleanup() {
    container rm -f "$SANDBOX_NAME" >/dev/null 2>&1 || true
    container rm -f "$PROXY_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

container network inspect "$NETWORK" >/dev/null 2>&1 \
    || container network create "$NETWORK" >/dev/null

stale() {
    # true when the image is missing or was not built today (UTC)
    local created
    created=$(container image inspect "$1" 2>/dev/null \
        | jq -r '.[0].configuration.creationDate // empty')
    [[ ${created:0:10} != "$(date -u +%Y-%m-%d)" ]]
}

if stale credentials-proxy; then
    echo "building credentials-proxy (not built today)..."
    container build --pull --no-cache \
        --tag credentials-proxy \
        --dns 203.0.113.113 \
        --file credentials-proxy/main.containerfile \
        credentials-proxy/
fi

if stale omp-sandbox; then
    echo "building omp-sandbox (not built today)..."
    infisical run -- \
        container build --pull --no-cache \
            --tag omp-sandbox \
            --dns 203.0.113.113 \
            --secret id=ca_cert,env=CREDENTIALS_PROXY_CA_CERT \
            --file omp-sandbox/main.containerfile \
            omp-sandbox/
fi

echo "starting credentials proxy..."
infisical run -- \
    container run --rm -d \
        --name "$PROXY_NAME" \
        --network "$NETWORK" \
        --env OPENROUTER_API_KEY \
        --env CREDENTIALS_PROXY_SERVER_CERT \
        --env CREDENTIALS_PROXY_SERVER_KEY \
        --env ENVOY_UID=0 \
        --dns 203.0.113.113 \
        credentials-proxy >/dev/null

PROXY_IP=
deadline=$((SECONDS + 20))
until [[ $(container inspect "$PROXY_NAME" 2>/dev/null \
            | jq -r '.[0].status.state // empty') == running ]] \
        && PROXY_IP=$(container inspect "$PROXY_NAME" 2>/dev/null \
            | jq -r '.[0].status.networks[0].ipv4Address | sub("/.*";"") // empty') \
        && [[ -n $PROXY_IP ]] \
        && nc -z "$PROXY_IP" 443 2>/dev/null; do
    if (( SECONDS >= deadline )); then
        echo "credentials-proxy failed to come up; logs:" >&2
        container logs "$PROXY_NAME" 2>&1 | tail -20 >&2
        exit 1
    fi
    sleep 0.5
done

WORKSPACE="${WORKSPACE:-$CALLER_CWD}"
if [[ $# -eq 0 ]]; then
    set -- omp  # default command: interactive omp
fi

container run --rm -it \
    --name "$SANDBOX_NAME" \
    --network "$NETWORK" \
    --dns 203.0.113.113 \
    --env OPENROUTER_PROXY_IP="$PROXY_IP" \
    --volume "$WORKSPACE:/workspace" \
    --workdir /workspace \
    omp-sandbox "$@"
