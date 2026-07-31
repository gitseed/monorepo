#!/bin/bash
# Runs the omp sandbox against the credentials-proxy.
#
#   ./run.sh                 # interactive omp, cwd mounted at /workspace
#   ./run.sh bash            # plain shell in the sandbox
#   WORKSPACE=~/other ./run.sh
#
# Discovers the proxy container's address and injects it into the sandbox,
# whose entrypoint maps openrouter.ai to it in /etc/hosts.
set -euo pipefail
CALLER_CWD=$PWD
cd "$(dirname "$0")"

PROXY_IP=$(container inspect credentials-proxy 2>/dev/null \
    | jq -r '.[0].status.networks[0].ipv4Address | sub("/.*"; "")')

if [[ -z "$PROXY_IP" || "$PROXY_IP" == "null" ]]; then
    echo "credentials-proxy is not running; start it with ../credentials-proxy/run.sh" >&2
    exit 1
fi

WORKSPACE="${WORKSPACE:-$CALLER_CWD}"

if [[ $# -eq 0 ]]; then
    set -- omp
fi

exec container run --rm -it \
    --network agent \
    --dns 203.0.113.113 \
    --env OPENROUTER_PROXY_IP="$PROXY_IP" \
    --volume "$WORKSPACE:/workspace" \
    --workdir /workspace \
    omp-sandbox "$@"
