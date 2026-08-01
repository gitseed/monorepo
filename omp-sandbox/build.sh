#!/bin/bash
# Builds the omp-sandbox image. The CA cert travels as a build secret straight
# from infisical; .infisical.json (repo root, tofu-generated) supplies project
# and environment, so no flags are needed.
#
# Always --no-cache: buildkit never cache-busts on secret contents, so after
# a CA rotation a cached build would ship the stale CA.
set -euo pipefail
cd "$(dirname "$0")/.."

infisical run -- \
    container build --pull --no-cache \
    --tag omp-sandbox \
    --dns 203.0.113.113 \
    --secret id=ca_cert,env=CREDENTIALS_PROXY_CA_CERT \
    --file omp-sandbox/main.containerfile \
    omp-sandbox/
