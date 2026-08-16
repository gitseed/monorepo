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

# DeepSeek Harness — developer preview, so pinned; upstream promises
# compatibility-breaking changes, re-baseline deliberately. The bin's
# node shebang lands on the bun symlink above — intentional: whether
# dsh works on bun is part of the spike.
#
# gcc, g++, make, and python3 are the build-time floor for that install:
# dsh's native modules (node-pty) ship no linux-arm64 prebuild, so bun
# falls back to node-gyp and compiles them.
ARG DSH_VERSION=0.1.0-rc.6
RUN dnf --assumeyes --setopt=install_weak_deps=False install \
        gcc \
        gcc-c++ \
        make \
        python3 \
    && dnf clean all
RUN bun add -g @deepseek-ai/dsh@${DSH_VERSION} \
    && ln -sf /root/.bun/bin/dsh /usr/local/bin/dsh

# pkl — Apple Pkl CLI config language.
ARG PKL_VERSION=0.32.1
ARG PKL_SHA256=a76d2dd47da435a8f911b0347373f47c7e59ea54fb75ff846d20b8df10dba058
RUN curl -fsSL -o /usr/local/bin/pkl \
        "https://github.com/apple/pkl/releases/download/${PKL_VERSION}/pkl-linux-aarch64" \
    && echo "${PKL_SHA256}  /usr/local/bin/pkl" | sha256sum --check \
    && chmod 0755 /usr/local/bin/pkl
RUN --mount=type=secret,id=ca_cert,target=/ca.pem \
    cp /ca.pem /etc/pki/ca-trust/source/anchors/sandbox-local-ca.pem \
    && update-ca-trust extract

# Bun's fetch ignores the system trust store.
ENV NODE_EXTRA_CA_CERTS=/etc/pki/ca-trust/source/anchors/sandbox-local-ca.pem

# So do the aws CLI and boto3 (bundled CA file); point them at the extracted
# system bundle, which includes the local CA.
ENV AWS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt

# No-graphical Emacs as the default editor.
ENV EDITOR=emacs-nox

# Emacs init — fixes fn+right (End) which was broken because \e[4~ maps to
# [select] instead of [end] in the xterm terminfo. The init overrides this
# in input-decode-map so both Home and End work in any cursor key mode.
# Works regardless of TERM — input-decode-map is always active.
COPY emacs-init.el /root/.emacs.d/init.el

# Harness home, pre-initialized: the profile manifest mirrors dsh's own
# web template (bundles resolve from the dsh installation, so the profile
# needs no node_modules until out-of-tree plugins are installed), the
# patch layer points the default model at the OpenRouter route, and
# settings.yaml mounts that route with the credential reference the
# proxy-unlocked env var satisfies.
COPY dsh/package.json /root/.dsh/profiles/web/package.json
COPY dsh/pnpm-workspace.yaml /root/.dsh/profiles/web/pnpm-workspace.yaml
COPY dsh/cordis.patch.yml /root/.dsh/profiles/web/cordis.patch.yml
COPY dsh/settings.yaml /root/.dsh/settings.yaml

# git SSH commit signing — the entrypoint sets up identity and signing
# config before handing off to the main process (needs gh CLI + proxy-injected token).
COPY entrypoint.sh /entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
