#!/bin/bash
# Builds the credentials-proxy image. No secrets involved: envoy reads
# OPENROUTER_API_KEY and the TLS cert+key from its environment at run time.
set -euo pipefail
cd "$(dirname "$0")/.."

container build --pull --no-cache \
    --tag credentials-proxy \
    --dns 203.0.113.113 \
    --file credentials-proxy/main.containerfile \
    credentials-proxy/
