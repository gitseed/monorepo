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

# Deno — pinned. dsh's engines nominally name Node, but Deno's node
# compatibility covers the APIs dsh needs (node:module.stripTypeScriptTypes,
# node:vm, node:sqlite, worker_threads all probed present in 2.9.5). Bun,
# which this image used to run, fails hard: even the latest 1.3.14 lacks
# node:module.stripTypeScriptTypes, so dsh's plugin tree never loads.
ARG DENO_VERSION=2.9.5
ARG DENO_SHA256=6b7cae3a8fc4385a59dea3146fcb8bad7fea4230e0ad36a8c692afacbc254be0
RUN curl -fsSL "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-aarch64-unknown-linux-gnu.zip" \
        -o /tmp/deno.zip \
    && echo "${DENO_SHA256}  /tmp/deno.zip" | sha256sum --check \
    && unzip -o /tmp/deno.zip -d /usr/local/bin \
    && chmod 0755 /usr/local/bin/deno \
    && ln -s /usr/local/bin/deno /usr/local/bin/node \
    && rm -f /tmp/deno.zip

# DeepSeek Harness — developer preview, version pinned in
# dsh/host-package.json; upstream promises compatibility-breaking
# changes, re-baseline deliberately.
#
# Installed as a local npm project, not a global bin: dsh's native
# modules (node-pty, Node-API) load only with a local node_modules.
#
# gcc, g++, make, and python3 are the build-time floor for the install:
# node-pty ships no linux prebuilds, so its install script falls back
# to node-gyp and compiles. The node symlink above (deno in node mode,
# detected via argv[0]) fields the bare `node` that node-gyp and the
# lifecycle scripts spawn. CI=true keeps deno install non-interactive.
RUN dnf --assumeyes --setopt=install_weak_deps=False install \
        gcc \
        gcc-c++ \
        make \
        python3 \
    && dnf clean all
RUN deno install -g npm:node-gyp \
    && ln -sf /root/.deno/bin/node-gyp /usr/local/bin/node-gyp
COPY dsh/host-package.json /opt/dsh/package.json
RUN cd /opt/dsh && CI=true deno install
COPY --chmod=0755 dsh/dsh /usr/local/bin/dsh

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

# Kept for any tool that honors it; deno itself takes the proxy CA via
# --ca in the dsh wrapper (its TLS stack does not read the OS store).
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
