# syntax=docker/dockerfile:1

# omp coding-agent sandbox. No real credentials inside: the only model
# endpoint reachable with valid auth is https://openrouter.ai, which the
# runner routes to the envoy proxy container (the compose service's
# extra_hosts maps openrouter.ai to the proxy's IP in /etc/hosts), where
# envoy injects the real API key.
#
# The CA cert arrives as a build secret straight from infisical; no disk
# files, no committed material (from monorepo root; or just run
# omp-sandbox/scripts/up.sh):
#
#   infisical run -- \
#     docker build --pull --no-cache \
#       --tag omp-sandbox \
#       --secret id=ca_cert,env=CREDENTIALS_PROXY_CA_CERT \
#       --file omp-sandbox/container/main.containerfile \
#       omp-sandbox/container/
#
# Run via omp-sandbox/scripts/up.sh, which discovers the proxy address and
# wires it up.

FROM quay.io/fedora/fedora:42

RUN dnf --assumeyes --setopt=install_weak_deps=False install \
        ca-certificates \
        curl \
        diffutils \
        findutils \
        git \
        gzip \
        less \
        openssh-clients \
        procps-ng \
        tar \
        unzip \
        which \
    && dnf clean all

# Bun instead of dnf's nodejs (~90MB unpacked vs the full nodejs dep
# chain); the node symlink makes node-expecting tooling fall onto bun.
# Platform binary pulled straight from the npm registry tarball, pinned
# by version and sha512.
ARG BUN_VERSION=1.3.14
ARG BUN_SHA512=5f94ac3d91ecfa260ef11fde7c8711b5cee04f64360e03df9620b1124c7871706e9b0930d1cfc4b0730dc07dc4806a420da67b21854f869086ff104e40713067
RUN curl -fsSL "https://registry.npmjs.org/@oven/bun-linux-aarch64/-/bun-linux-aarch64-${BUN_VERSION}.tgz" \
        -o /tmp/bun.tgz \
    && echo "${BUN_SHA512}  /tmp/bun.tgz" | sha512sum --check \
    && tar -xzf /tmp/bun.tgz -C /tmp \
    && install -m 0755 /tmp/package/bin/bun /usr/local/bin/bun \
    && ln -s /usr/local/bin/bun /usr/local/bin/node \
    && rm -rf /tmp/package /tmp/bun.tgz

# Trust the local CA that signs the proxy's openrouter.ai certificate.
RUN --mount=type=secret,id=ca_cert,target=/ca.pem \
    cp /ca.pem /etc/pki/ca-trust/source/anchors/omp-sandbox-local-ca.pem \
    && update-ca-trust extract

# Bun's fetch ignores the system store; omp honours NODE_EXTRA_CA_CERTS for
# every provider request, so point it at the same CA explicitly.
ENV NODE_EXTRA_CA_CERTS=/etc/pki/ca-trust/source/anchors/omp-sandbox-local-ca.pem

# Placeholder: makes the openrouter provider "available" inside the sandbox.
# envoy's credential injector overwrites the header with the real key, so
# this value is never usable on its own.
ENV OPENROUTER_API_KEY=dummy-replaced-by-proxy

# Pre-seeded config: skip the first-run wizard and pin the default model.
# Auth itself comes from the proxy, not from anything here.
COPY agent-config.yml /root/.omp/agent/config.yml

CMD ["bash"]
