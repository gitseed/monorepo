ARG AGENT_VAULT_IMAGE=infisical/agent-vault:0.39.0
FROM ${AGENT_VAULT_IMAGE} AS agent-vault-upstream

# Agent Vault's published image declares /data as a persistent volume. This
# final stage deliberately does not: every vault database, CA, session, and
# cached secret disappears with the container.
FROM alpine:3.24.1

RUN apk add --no-cache ca-certificates curl jq \
    && addgroup -S agentvault \
    && adduser -S -G agentvault -u 65532 agentvault \
    && mkdir -p /data/.agent-vault \
    && chown -R agentvault:agentvault /data

COPY --from=agent-vault-upstream /usr/local/bin/agent-vault /usr/local/bin/agent-vault
COPY services.yaml /etc/agent-vault/services.yaml
COPY scripts/import-secrets.sh /usr/local/bin/import-agent-secrets

RUN chmod +x /usr/local/bin/import-agent-secrets

ENV HOME=/data
EXPOSE 14321 14322
USER agentvault
ENTRYPOINT ["/usr/local/bin/agent-vault"]
CMD ["server", "--host", "0.0.0.0", "--port", "14321"]
