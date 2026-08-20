# syntax=docker/dockerfile:1

FROM docker.io/envoyproxy/envoy:v1.39-latest AS render
ARG PKL_VERSION=0.28.2
ARG PKL_SHA256=ed04d0175fd3ceaddcb5c35af657de6a96cd8018cfca9f7d14e738c98b4782bf
ADD --checksum=sha256:${PKL_SHA256} --chmod=0755 \
    https://github.com/apple/pkl/releases/download/${PKL_VERSION}/pkl-linux-aarch64 \
    /usr/local/bin/pkl
COPY container/envoy.pkl /envoy.pkl
COPY container/upstreams.yml /upstreams.yml
COPY sigv4/signing_names.json /signing_names.json
COPY sigv4/regions.json /regions.json
RUN /usr/local/bin/pkl eval --format yaml /envoy.pkl --output-path /envoy.yaml

FROM docker.io/envoyproxy/envoy:v1.39-latest
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libcap2-bin \
    && setcap 'cap_net_bind_service=+ep' /usr/local/bin/envoy \
    && rm -rf /var/lib/apt/lists/*
COPY --from=render --chmod=0444 /envoy.yaml /etc/envoy/envoy.yaml
