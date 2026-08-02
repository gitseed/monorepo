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

# ca-certificates: the system trust bundle that envoy.yaml's upstream
# validation_context verifies upstream certs against -- without it the
# pinning has nothing to anchor to (and envoy refuses to start, failing
# closed).
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libcap2-bin \
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/envoy \
    && apt-get purge -y libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=0444 envoy.yaml /etc/envoy/envoy.yaml

# Resolver discovery runs before envoy: parse the host-forwarder address
# out of docker's generated resolv.conf (# ExtServers: [host(<ip>)]),
# point this container's resolver at it, and fail the container (not the
# request) if parsing or the alias-escape check fails -- the compose
# healthcheck is a bare TCP connect and envoy binds its listener before
# DNS health is known, so the die-early path is the only loud one.
COPY --chmod=0755 proxy-entrypoint.sh /usr/local/bin/proxy-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/proxy-entrypoint.sh"]
# Wikipedia rule of Dockerfile footguns: setting ENTRYPOINT resets CMD to
# null, so re-declare the base image's command explicitly or the exec
# chain hands nothing to envoy (observed: su-exec usage banner, exit 1).
CMD ["envoy", "-c", "/etc/envoy/envoy.yaml"]
