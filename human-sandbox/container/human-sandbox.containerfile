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
        jq \
        yq \
        awscli2 \
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

# pkl — Apple Pkl CLI config language.
ARG PKL_VERSION=0.32.1
ARG PKL_SHA256=a76d2dd47da435a8f911b0347373f47c7e59ea54fb75ff846d20b8df10dba058
RUN curl -fsSL -o /usr/local/bin/pkl \
        "https://github.com/apple/pkl/releases/download/${PKL_VERSION}/pkl-linux-aarch64" \
    && echo "${PKL_SHA256}  /usr/local/bin/pkl" | sha256sum --check \
    && chmod 0755 /usr/local/bin/pkl

# OpenTofu — the tofu binary, pinned and checksummed like the other tools.
ARG TOFU_VERSION=1.12.5
ARG TOFU_SHA256=e67e9da2b1ddf5050ebee62a584cb826eafe1dfd3827d7ec20899ac62791ed1a
RUN curl -fsSL -o /tmp/tofu.tar.gz \
        "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_arm64.tar.gz" \
    && echo "${TOFU_SHA256}  /tmp/tofu.tar.gz" | sha256sum --check \
    && tar -xzf /tmp/tofu.tar.gz -C /tmp tofu \
    && install -m 0755 /tmp/tofu /usr/local/bin/tofu \
    && rm -f /tmp/tofu*

# Keep tofu's data dir out of .terraform: the host's .terraform holds darwin
# provider binaries the container can't execute, and .sandbox_tofu lives on
# the mounted /workspace, so the linux provider cache persists across sessions.
ENV TF_DATA_DIR=.sandbox_tofu

# No-graphical Emacs as the default editor.
ENV EDITOR=emacs-nox

# Emacs init — fixes fn+right (End) which was broken because \e[4~ maps to
# [select] instead of [end] in the xterm terminfo. The init overrides this
# in input-decode-map so both Home and End work in any cursor key mode.
# Works regardless of TERM — input-decode-map is always active.
COPY emacs-init.el /root/.emacs.d/init.el

# git SSH commit signing — the entrypoint sets up identity and signing
# config before handing off to the main process (needs gh CLI + GITHUB_TOKEN
# exposed into the environment).
COPY entrypoint.sh /entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
