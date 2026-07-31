# syntax=docker/dockerfile:1

# Build:
#   container build --pull --no-cache \
#     --tag credentials-proxy \
#     --dns 203.0.113.113 \
#     --file main.containerfile \
#     .
#
# Run: ../../credentials-proxy/run.sh (or see NOTES.md)
#
# The runtime mounts ./certs at /etc/envoy/certs (TLS listener on 443)
# and sets ENVOY_UID=0 so envoy keeps root and can bind 443.

FROM docker.io/envoyproxy/envoy:v1.39-latest

COPY --chmod=0444 envoy.yaml /etc/envoy/envoy.yaml
