# syntax=docker/dockerfile:1

# Credential-injecting envoy proxy. Built and run by scripts/up.sh;
# server cert+key arrive via the environment, no cert files.

# Render stage: envoy.pkl -> envoy.yaml at build time. The pinned pkl
# binary exists only in this discarded stage.
FROM docker.io/envoyproxy/envoy:v1.39-latest AS render
ARG PKL_VERSION=0.28.2
ARG PKL_SHA256=ed04d0175fd3ceaddcb5c35af657de6a96cd8018cfca9f7d14e738c98b4782bf
ADD --checksum=sha256:${PKL_SHA256} --chmod=0755 \
    https://github.com/apple/pkl/releases/download/${PKL_VERSION}/pkl-linux-aarch64 \
    /usr/local/bin/pkl
COPY envoy.pkl /envoy.pkl
RUN /usr/local/bin/pkl eval --format yaml /envoy.pkl --output-path /envoy.yaml

FROM docker.io/envoyproxy/envoy:v1.39-latest

# ca-certificates anchors envoy.pkl's upstream cert verification (envoy
# refuses to start without it). setcap lets envoy bind :443 while still
# dropping to its unprivileged default user.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libcap2-bin \
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/envoy \
    && apt-get purge -y libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

COPY --from=render --chmod=0444 /envoy.yaml /etc/envoy/envoy.yaml
