#!/bin/bash
# Starts the credentials-proxy (envoy) on the shared container network.
# The real OpenRouter key and the TLS server certificate are pulled from
# infisical and handed to envoy purely through the environment; no secret
# material ever touches this host's disk.
# Certificates are tofu-managed: agent-secrets/tofu/credentials_proxy_cert.tf
set -euo pipefail
cd "$(dirname "$0")"

NETWORK=agent

if container inspect credentials-proxy >/dev/null 2>&1; then
    echo "credentials-proxy already running:"
    container inspect credentials-proxy | jq -r '.[] | "  \(.configuration.id) at \(.status.networks[].ipv4Address | sub("/.*"; ""))"'
    exit 0
fi

infisical run --env global --projectId b4d3e8f0-dec8-4bb7-bc71-bba7dd3401f0 -- \
    container run --rm -d \
        --name credentials-proxy \
        --network "$NETWORK" \
        --env OPENROUTER_API_KEY \
        --env CREDENTIALS_PROXY_SERVER_CERT \
        --env CREDENTIALS_PROXY_SERVER_KEY \
        --env ENVOY_UID=0 \
        --dns 203.0.113.113 \
        --publish 127.0.0.1:10000:10000 \
        credentials-proxy

sleep 1
container inspect credentials-proxy \
    | jq -r '.[] | "credentials-proxy at \(.status.networks[].ipv4Address | sub("/.*"; ""))"'
