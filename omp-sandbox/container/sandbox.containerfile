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
        gh \
        bat \
        eza \
        fzf \
        hexyl \
        yq \
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


# sd — intuitive sed replacement (not in Fedora repos).
ARG SD_VERSION=1.1.0
ARG SD_SHA256=ec8c93c0533ff21f4851d11566808d4082544baf063d9b96ea77c27e98b7cd99
RUN curl -fsSL -o /tmp/sd.tar.gz \
        "https://github.com/chmln/sd/releases/download/v${SD_VERSION}/sd-v${SD_VERSION}-aarch64-unknown-linux-musl.tar.gz" \
    && echo "${SD_SHA256}  /tmp/sd.tar.gz" | sha256sum --check \
    && tar -xzf /tmp/sd.tar.gz -C /tmp \
    && install -m 0755 /tmp/sd-v${SD_VERSION}-aarch64-unknown-linux-musl/sd /usr/local/bin/sd \
    && rm -rf /tmp/sd*

# pkl — Apple Pkl CLI config language.
ARG PKL_VERSION=0.32.1
ARG PKL_SHA256=a76d2dd47da435a8f911b0347373f47c7e59ea54fb75ff846d20b8df10dba058
RUN curl -fsSL -o /usr/local/bin/pkl \
        "https://github.com/apple/pkl/releases/download/${PKL_VERSION}/pkl-linux-aarch64" \
    && echo "${PKL_SHA256}  /usr/local/bin/pkl" | sha256sum --check \
    && chmod 0755 /usr/local/bin/pkl
RUN --mount=type=secret,id=ca_cert,target=/ca.pem \
    cp /ca.pem /etc/pki/ca-trust/source/anchors/omp-sandbox-local-ca.pem \
    && update-ca-trust extract

# Bun's fetch ignores the system trust store.
ENV NODE_EXTRA_CA_CERTS=/etc/pki/ca-trust/source/anchors/omp-sandbox-local-ca.pem

# Placeholder so omp considers the provider available.
ENV OPENROUTER_API_KEY=dummy-replaced-by-proxy
# Placeholder so gh adds an Authorization header that the proxy overwrites.
ENV GITHUB_TOKEN=dummy-replaced-by-proxy
ENV FIRECRAWL_API_KEY=dummy-replaced-by-proxy

COPY agent-config.yml /root/.omp/agent/config.yml
COPY APPEND_SYSTEM.md /root/.omp/agent/APPEND_SYSTEM.md
# Morph Fast Apply extension — calls morph-v3-fast via OpenRouter.
COPY extensions/morph.ts /root/.omp/agent/extensions/morph.ts

# OpenRouter Advisor tools — each JSON in advisers/ defines one advisor tool.
COPY extensions/openrouter-advisor.ts /root/.omp/agent/extensions/openrouter-advisor.ts
COPY extensions/advisors/ /root/.omp/agent/extensions/advisors/

# git SSH commit signing — the entrypoint sets up identity and signing
# config before handing off to the main process (needs gh CLI + proxy-injected token).
COPY entrypoint.sh /entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
