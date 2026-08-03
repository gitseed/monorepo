# syntax=docker/dockerfile:1

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

# Bun instead of dnf's nodejs, which is much larger.
ARG BUN_VERSION=1.3.14
ARG BUN_SHA512=5f94ac3d91ecfa260ef11fde7c8711b5cee04f64360e03df9620b1124c7871706e9b0930d1cfc4b0730dc07dc4806a420da67b21854f869086ff104e40713067
RUN curl -fsSL "https://registry.npmjs.org/@oven/bun-linux-aarch64/-/bun-linux-aarch64-${BUN_VERSION}.tgz" \
        -o /tmp/bun.tgz \
    && echo "${BUN_SHA512}  /tmp/bun.tgz" | sha512sum --check \
    && tar -xzf /tmp/bun.tgz -C /tmp \
    && install -m 0755 /tmp/package/bin/bun /usr/local/bin/bun \
    && ln -s /usr/local/bin/bun /usr/local/bin/node \
    && rm -rf /tmp/package /tmp/bun.tgz

RUN curl -fsSL https://raw.githubusercontent.com/can1357/oh-my-pi/main/scripts/install.sh \
        | PI_INSTALL_DIR=/usr/local/bin sh -s -- --binary

# RTK — CLI proxy that compresses bash output for LLM context.
ARG RTK_VERSION=0.44.2
ARG RTK_SHA256=5cd3f7fa2697faf9e5b77a10ce4e699006e02d4752d792f06550697eb4b8e8a9
RUN curl -fsSL -o /tmp/rtk.tar.gz \
        "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/rtk-aarch64-unknown-linux-gnu.tar.gz" \
    && echo "${RTK_SHA256}  /tmp/rtk.tar.gz" | sha256sum --check \
    && tar -xzf /tmp/rtk.tar.gz -C /usr/local/bin/ \
    && chmod 0755 /usr/local/bin/rtk \
    && rm -f /tmp/rtk.tar.gz

# Install the RTK Pi extension and relocate it to the omp extensions directory.
RUN rtk init -g --agent pi --auto-patch \
    && mkdir -p /root/.omp/agent/extensions \
    && cp /root/.pi/agent/extensions/rtk.ts /root/.omp/agent/extensions/rtk.ts \
    && rm -rf /root/.pi

RUN --mount=type=secret,id=ca_cert,target=/ca.pem \
    cp /ca.pem /etc/pki/ca-trust/source/anchors/omp-sandbox-local-ca.pem \
    && update-ca-trust extract

# Bun's fetch ignores the system trust store.
ENV NODE_EXTRA_CA_CERTS=/etc/pki/ca-trust/source/anchors/omp-sandbox-local-ca.pem

# Placeholder so omp considers the provider available.
ENV OPENROUTER_API_KEY=dummy-replaced-by-proxy

COPY agent-config.yml /root/.omp/agent/config.yml

CMD ["bash"]
