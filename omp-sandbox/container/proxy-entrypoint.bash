#!/bin/bash
# Envoy's generic credential injector can't transform secrets, and github.com's
# git endpoints only accept Basic auth. Derive the Basic form of the PAT here.
set -euo pipefail
GITHUB_TOKEN_BASIC=$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 --wrap=0)
export GITHUB_TOKEN_BASIC
exec /docker-entrypoint.sh "$@"
