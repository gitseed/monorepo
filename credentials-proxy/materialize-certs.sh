#!/bin/bash
# Materializes the tofu-managed proxy certificates from infisical into ./certs.
# Source of truth: agent-secrets/tofu/credentials_proxy_cert.tf
# The CA private key never leaves tofu state / infisical; only the material
# the proxy and sandbox images need is fetched here.
set -euo pipefail
cd "$(dirname "$0")"

PROJECT_ID=b4d3e8f0-dec8-4bb7-bc71-bba7dd3401f0

mkdir -p certs

materialize() {
    local secret_name=$1 target=$2
    infisical secrets get "$secret_name" \
        --env global --projectId "$PROJECT_ID" --plain \
        | sed -e '$a\' \
        > "certs/$target"
}

materialize CREDENTIALS_PROXY_CA_CERT ca.pem
materialize CREDENTIALS_PROXY_SERVER_CERT server.pem
materialize CREDENTIALS_PROXY_SERVER_KEY server.key

chmod 0644 certs/ca.pem certs/server.pem
chmod 0600 certs/server.key

echo "materialized certs/{ca.pem,server.pem,server.key} from infisical"
