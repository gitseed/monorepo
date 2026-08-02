# syntax=docker/dockerfile:1

# omp coding-agent sandbox. No real credentials inside: the upstream
# hostnames resolve to the credential-injecting proxy (compose links),
# and the only key material baked in is the proxy's CA cert, which
# arrives as a build secret. Built and run by scripts/up.sh.

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

# Bun instead of dnf's nodejs (much smaller); the node symlink catches
# node-expecting tooling. Pinned by version and sha512.
ARG BUN_VERSION=1.3.14
ARG BUN_SHA512=5f94ac3d91ecfa260ef11fde7c8711b5cee04f64360e03df9620b1124c7871706e9b0930d1cfc4b0730dc07dc4806a420da67b21854f869086ff104e40713067
RUN curl -fsSL "https://registry.npmjs.org/@oven/bun-linux-aarch64/-/bun-linux-aarch64-${BUN_VERSION}.tgz" \
        -o /tmp/bun.tgz \
    && echo "${BUN_SHA512}  /tmp/bun.tgz" | sha512sum --check \
    && tar -xzf /tmp/bun.tgz -C /tmp \
    && install -m 0755 /tmp/package/bin/bun /usr/local/bin/bun \
    && ln -s /usr/local/bin/bun /usr/local/bin/node \
    && rm -rf /tmp/package /tmp/bun.tgz

# The omp prebuilt binary -- what this image exists to sandbox.
RUN curl -fsSL https://raw.githubusercontent.com/can1357/oh-my-pi/main/scripts/install.sh \
        | PI_INSTALL_DIR=/usr/local/bin sh -s -- --binary

# Trust the local CA that signs the proxy's openrouter.ai certificate.
RUN --mount=type=secret,id=ca_cert,target=/ca.pem \
    cp /ca.pem /etc/pki/ca-trust/source/anchors/omp-sandbox-local-ca.pem \
    && update-ca-trust extract

# Bun's fetch ignores the system store; point it at the same CA.
ENV NODE_EXTRA_CA_CERTS=/etc/pki/ca-trust/source/anchors/omp-sandbox-local-ca.pem

# Placeholders so omp considers these providers available; the proxy
# overwrites the real Authorization header on the way out.
ENV OPENROUTER_API_KEY=dummy-replaced-by-proxy
ENV IAN_NEURAWATT_API_TOKEN=dummy-replaced-by-proxy

# Pre-seeded config: skip the first-run wizard, pin the default model,
# define the neurawatt provider.
COPY agent-config.yml /root/.omp/agent/config.yml
COPY agent-models.yml /root/.omp/agent/models.yml

CMD ["bash"]
