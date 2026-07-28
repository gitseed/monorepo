ARG AGENT_VAULT_IMAGE=infisical/agent-vault:0.39.0
FROM ${AGENT_VAULT_IMAGE} AS agent-vault-upstream

FROM oven/bun:1.3.14-debian

USER root

# The same core editing/search/browser tools used by the Lightning agent,
# without its AWS, Kubernetes, or nested-container credentials and machinery.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        chromium \
        curl \
        gh \
        git \
        jq \
        less \
        openssh-client \
        procps \
        python3 \
        python3-pip \
        ripgrep \
        fd-find \
        sqlite3 \
        unzip \
        vim-tiny \
        wget \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/*

RUN bun install --global @oh-my-pi/pi-coding-agent@17.1.6 \
    && omp --version

COPY --from=agent-vault-upstream /usr/local/bin/agent-vault /usr/local/bin/agent-vault
COPY scripts/entrypoint.bash /usr/local/bin/agent-sandbox-entrypoint

RUN chmod +x /usr/local/bin/agent-sandbox-entrypoint \
    && git config --global user.name "Agent Sandbox" \
    && git config --global user.email "agent@agent-sandbox.local"

ENV AGENT_VAULT_TELEMETRY=false
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/agent-sandbox-entrypoint"]
CMD []
