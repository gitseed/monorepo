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

# Render stage: envoy.pkl -> envoy.yaml during the build, so the config
# source of truth is the only thing committed and there is nothing to
# regenerate by hand or drift-check. The pkl binary (version + sha256
# pinned, matching how the sandbox pins bun) lives only in this
# discarded stage; the final image never contains it.
FROM docker.io/envoyproxy/envoy:v1.39-latest AS render
ARG PKL_VERSION=0.28.2
ARG PKL_SHA256=ed04d0175fd3ceaddcb5c35af657de6a96cd8018cfca9f7d14e738c98b4782bf
ADD --checksum=sha256:${PKL_SHA256} --chmod=0755 \
    https://github.com/apple/pkl/releases/download/${PKL_VERSION}/pkl-linux-aarch64 \
    /usr/local/bin/pkl
COPY envoy.pkl /envoy.pkl
RUN /usr/local/bin/pkl eval --format yaml /envoy.pkl --output-path /envoy.yaml

FROM docker.io/envoyproxy/envoy:v1.39-latest

# ca-certificates: the system trust bundle that envoy.pkl's upstream
# validation_context verifies upstream certs against -- without it the
# pinning has nothing to anchor to (and envoy refuses to start, failing
# closed).
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libcap2-bin \
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/envoy \
    && apt-get purge -y libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

COPY --from=render --chmod=0444 /envoy.yaml /etc/envoy/envoy.yaml
