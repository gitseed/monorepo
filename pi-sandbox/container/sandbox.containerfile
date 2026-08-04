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
        emacs-nox \
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

# pi coding agent. BUN_INSTALL=/usr/local links the `pi` bin into /usr/local/bin.
RUN BUN_INSTALL=/usr/local bun add -g @earendil-works/pi-coding-agent

# RTK — CLI proxy that compresses bash output for LLM context.
ARG RTK_VERSION=0.44.2
ARG RTK_SHA256=5cd3f7fa2697faf9e5b77a10ce4e699006e02d4752d792f06550697eb4b8e8a9
RUN curl -fsSL -o /tmp/rtk.tar.gz \
        "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/rtk-aarch64-unknown-linux-gnu.tar.gz" \
    && echo "${RTK_SHA256}  /tmp/rtk.tar.gz" | sha256sum --check \
    && tar -xzf /tmp/rtk.tar.gz -C /usr/local/bin/ \
    && chmod 0755 /usr/local/bin/rtk \
    && rm -f /tmp/rtk.tar.gz

# RTK Pi extension lands in /root/.pi/agent/extensions/rtk.ts.
RUN rtk init -g --agent pi --auto-patch

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
    cp /ca.pem /etc/pki/ca-trust/source/anchors/pi-sandbox-local-ca.pem \
    && update-ca-trust extract

# Bun's fetch ignores the system trust store.
ENV NODE_EXTRA_CA_CERTS=/etc/pki/ca-trust/source/anchors/pi-sandbox-local-ca.pem

# Placeholder so pi considers the provider available.
ENV OPENROUTER_API_KEY=dummy-replaced-by-proxy
# Placeholder so gh adds an Authorization header that the proxy overwrites.
ENV GITHUB_TOKEN=dummy-replaced-by-proxy
ENV FIRECRAWL_API_KEY=dummy-replaced-by-proxy

# No-graphical Emacs as the default editor.
ENV EDITOR=emacs-nox

COPY settings.json /root/.pi/agent/settings.json

# Memory extension — logs every turn to the shared postgres over its unix
# socket (mounted at /var/run/postgresql) via Bun's native SQL bindings.
COPY extensions/memory.ts /root/.pi/agent/extensions/memory.ts

# OpenRouter provider — registers the full tool-capable OpenRouter catalog
# with live metadata at startup (no models.json).
COPY extensions/openrouter.ts /root/.pi/agent/extensions/openrouter.ts

# git SSH commit signing — the entrypoint sets up identity and signing
# config before handing off to the main process (needs gh CLI + proxy-injected token).
COPY entrypoint.sh /entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
