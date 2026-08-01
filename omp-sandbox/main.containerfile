# syntax=docker/dockerfile:1

# omp coding-agent sandbox. No real credentials inside: the only model
# endpoint reachable with valid auth is https://openrouter.ai, which the
# entrypoint routes (via /etc/hosts, using $OPENROUTER_PROXY_IP) to the
# credentials-proxy container, where envoy injects the real API key.
#
# The CA cert arrives as a build secret straight from infisical; no disk
# files, no committed material:
#
#   infisical run --env global --projectId <project-id> -- \
#     container build --pull --no-cache \
#       --tag omp-sandbox \
#       --dns 203.0.113.113 \
#       --secret id=ca_cert,env=CREDENTIALS_PROXY_CA_CERT \
#       --file omp-sandbox/main.containerfile \
#       omp-sandbox/
#
# Run via omp-sandbox/run.sh, which discovers the proxy address and wires it up.

FROM quay.io/fedora/fedora:42

RUN dnf --assumeyes --setopt=install_weak_deps=False install \
        ca-certificates \
        curl \
        findutils \
        git \
        gzip \
        less \
        nodejs \
        openssh-clients \
        procps-ng \
        python3 \
        tar \
        unzip \
        which \
    && dnf clean all

# omp prebuilt binary (linux/arm64, glibc).
RUN curl -fsSL https://raw.githubusercontent.com/can1357/oh-my-pi/main/scripts/install.sh \
        | PI_INSTALL_DIR=/usr/local/bin sh -s -- --binary

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

COPY --chmod=0755 entrypoint.sh /usr/local/bin/omp-sandbox-entrypoint
ENTRYPOINT ["/usr/local/bin/omp-sandbox-entrypoint"]
CMD ["bash"]
