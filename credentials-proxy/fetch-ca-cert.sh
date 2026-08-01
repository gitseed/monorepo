#!/bin/bash
# Fetches the public CA certificate into ./certs/ca.pem — the only cert
# material anything local ever needs: the sandbox image build COPYs it
# into the trust store. The envoy proxy gets its server cert+key through
# the environment instead (see run.sh), so no private key touches disk.
# Source of truth: agent-secrets/tofu/credentials_proxy_cert.tf
set -euo pipefail
cd "$(dirname "$0")"

PROJECT_ID=b4d3e8f0-dec8-4bb7-bc71-bba7dd3401f0

mkdir -p certs
infisical secrets get CREDENTIALS_PROXY_CA_CERT \
    --env global --projectId "$PROJECT_ID" --plain \
    | sed -e '$a\' \
    > certs/ca.pem
chmod 0644 certs/ca.pem

echo "fetched certs/ca.pem from infisical"
