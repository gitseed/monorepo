# syntax=docker/dockerfile:1

# dsh-tui — Go TUI frontend for dsh's SDK jsonrpc runtime. Source comes in
# through the dsh-tui-src additional build context (compose.pkl).
FROM docker.io/library/golang:1.26 AS dsh-tui-build
WORKDIR /src
COPY --from=dsh-tui-src . .
RUN CGO_ENABLED=0 go build -o /out/dsh-tui ./cmd/dsh-tui

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

# Node — pinned; dsh's engines require ^22.19.0 || >=24.0.0. The other
# candidates both fail: bun (even unreleased master) has no
# node:module.stripTypeScriptTypes, which dsh's code-runtime imports
# at module scope, and deno 2.9.5 deadlocks mid npm install
# (denoland/deno#36599).
ARG NODE_VERSION=22.23.2
ARG NODE_SHA256=fff4078c5def658577f92c88db7db3bc0072924bfb93fe52c1e744a54e94abb8
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-arm64.tar.xz" \
        -o /tmp/node.tar.xz \
    && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum --check \
    && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
    && rm -f /tmp/node.tar.xz

# DeepSeek Harness — developer preview, so pinned; upstream promises
# compatibility-breaking changes, re-baseline deliberately.
#
# gcc, g++, make, and python3 are the build-time floor for the install:
# dsh's native modules (node-pty) ship no linux prebuilds, so npm
# falls back to node-gyp and compiles them.
ARG DSH_VERSION=0.1.0-rc.6
RUN dnf --assumeyes --setopt=install_weak_deps=False install \
        gcc \
        gcc-c++ \
        make \
        python3 \
        python3-pip \
    && dnf clean all
RUN npm install -g @deepseek-ai/dsh@${DSH_VERSION}

# dsh SDK runtime — the single-file jsonrpc agent dsh-tui drives. Ships in
# the runtime-bin wheel; same upstream release train as dsh, so same pin
# (PyPI spells the version without the dash). The symlink gives dsh-tui a
# stable DSH_RUNTIME_BIN across python minor bumps.
RUN pip3 install "deepseek-harness-sdk==${DSH_VERSION/-rc./rc}" \
    && ln -s "$(python3 -c 'from deepseek_harness_runtime import resolve_bundled_launch_args as r; print(r()[0])')" \
        /usr/local/bin/dsh-jsonrpc-agent
ENV DSH_RUNTIME_BIN=/usr/local/bin/dsh-jsonrpc-agent
COPY --from=dsh-tui-build /out/dsh-tui /usr/local/bin/dsh-tui
COPY dsh/tui.cordis.yml /root/.dsh/tui.cordis.yml

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

# Node honors NODE_EXTRA_CA_CERTS; the credentials proxy intercepts
# TLS with a local CA, so every upstream needs it in trust.
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
