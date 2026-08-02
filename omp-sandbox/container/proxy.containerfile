# syntax=docker/dockerfile:1

# Build (from the omp-sandbox dir; usually just run scripts/up.sh):
#   docker build --pull --no-cache \
#     --tag credentials-proxy \
#     --file container/proxy.containerfile \
#     container/
#
# Run via scripts/up.sh (per-session proxy; see ../README.md)
#
# Server cert+key arrive via the environment (infisical); no cert files.
# The envoy binary gets ONLY cap_net_bind_service so it can bind :443 while
# still dropping to the unprivileged envoy user it runs as by default.

FROM docker.io/envoyproxy/envoy:v1.39-latest

RUN apt-get update \
    && apt-get install -y --no-install-recommends libcap2-bin \
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/envoy \
    && apt-get purge -y libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=0444 envoy.yaml /etc/envoy/envoy.yaml
