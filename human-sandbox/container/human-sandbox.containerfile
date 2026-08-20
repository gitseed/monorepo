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
        sudo \
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

# OpenTofu — the tofu binary.
ARG TOFU_VERSION=1.12.5
ARG TOFU_SHA256=e67e9da2b1ddf5050ebee62a584cb826eafe1dfd3827d7ec20899ac62791ed1a
RUN curl -fsSL -o /tmp/tofu.tar.gz \
        "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_arm64.tar.gz" \
    && echo "${TOFU_SHA256}  /tmp/tofu.tar.gz" | sha256sum --check \
    && tar -xzf /tmp/tofu.tar.gz -C /tmp tofu \
    && install -m 0755 /tmp/tofu /usr/local/bin/tofu \
    && rm -f /tmp/tofu*

# starship prompt — not packaged in Fedora 42, so pinned like the rest.
ARG STARSHIP_VERSION=1.26.0
ARG STARSHIP_SHA256=dc30189378d2f2e287384e8a692d3f95ad1df64cf0e8c36aa9201516028aed6b
RUN curl -fsSL -o /tmp/starship.tar.gz \
        "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-aarch64-unknown-linux-musl.tar.gz" \
    && echo "${STARSHIP_SHA256}  /tmp/starship.tar.gz" | sha256sum --check \
    && tar -xzf /tmp/starship.tar.gz -C /tmp starship \
    && install -m 0755 /tmp/starship /usr/local/bin/starship \
    && rm -f /tmp/starship*

# The occupant: non-root with passwordless sudo. Compose must not set
# no-new-privileges — sudo is setuid and stops working under it.
RUN useradd --create-home human \
    && echo 'human ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/human \
    && chmod 440 /etc/sudoers.d/human \
    && echo 'eval "$(starship init bash)"' >> /home/human/.bashrc

# Keep tofu's data dir out of .terraform: the host's .terraform holds darwin
# provider binaries the container can't execute, and .sandbox_tofu lives on
# the mounted /workspace, so the linux provider cache persists across sessions.
ENV TF_DATA_DIR=.sandbox_tofu

ENV EDITOR=emacs-nox

# Emacs init — fixes fn+right (End) which was broken because \e[4~ maps to
# [select] instead of [end] in the xterm terminfo. The init overrides this
# in input-decode-map so both Home and End work in any cursor key mode.
# Works regardless of TERM — input-decode-map is always active.
COPY --chown=human:human emacs-init.el /home/human/.emacs.d/init.el

COPY --chown=human:human starship.toml /home/human/.config/starship.toml

COPY entrypoint.sh /entrypoint.sh

USER human
WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
