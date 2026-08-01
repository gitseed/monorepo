# syntax=docker/dockerfile:1

# Build:
#   container build --pull --no-cache \
#     --tag credentials-proxy \
#     --dns 203.0.113.113 \
#     --file main.containerfile \
#     .
#
# Run: ./run.sh (or see NOTES.md)
#
# Server cert+key arrive via the environment (infisical) and run.sh sets
# ENVOY_UID=0 so envoy keeps root and can bind 443. No cert files needed.

FROM docker.io/envoyproxy/envoy:v1.39-latest

COPY --chmod=0444 envoy.yaml /etc/envoy/envoy.yaml
