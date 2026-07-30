# syntax=docker/dockerfile:1

# Build:
#   container build --pull --no-cache \
#     --tag credentials-proxy \
#     --dns 203.0.113.113 \
#     --file main.containerfile \
#     .
#
# Run:
#   infisical run --env global --projectId <project-id> -- \
#     container run --rm -it \
#       --name credentials-proxy \
#       --env OPENROUTER_API_KEY \
#       --dns 203.0.113.113 \
#       --publish 127.0.0.1:10000:10000 \
#       credentials-proxy
#
# Then use http://127.0.0.1:10000/api/v1 as the OpenRouter base URL.

FROM docker.io/envoyproxy/envoy:v1.39-latest

COPY --chmod=0444 envoy.yaml /etc/envoy/envoy.yaml
