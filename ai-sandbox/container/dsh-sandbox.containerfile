# syntax=docker/dockerfile:1

# Spike: DeepSeek Harness (dsh) Web UI inside the ai-sandbox trust envelope.
# FROM ai-sandbox: the bun runtime, CA trust, and the git-signing
# entrypoint all come from the base image; compose adds the proxy env
# plumbing (dummy vars, links, dns) exactly as for the omp sandbox.
FROM ai-sandbox

# Developer-preview release, pinned — upstream promises compatibility-
# breaking changes. The bin's node shebang lands on this image's node
# symlink (bun), which is part of what the spike tests.
ARG DSH_VERSION=0.1.0-rc.6
RUN bun add -g @deepseek-ai/dsh@${DSH_VERSION} \
    && ln -sf /root/.bun/bin/dsh /usr/local/bin/dsh

# Harness home, pre-initialized: the profile manifest mirrors dsh's own
# web template (bundles resolve from the dsh installation, so the profile
# needs no node_modules until out-of-tree plugins are installed), the
# patch layer points the deployment default model at the OpenRouter
# route, and settings.yaml mounts that route with the credential
# reference the proxy-unlocked env var satisfies.
COPY dsh/package.json /root/.dsh/profiles/web/package.json
COPY dsh/pnpm-workspace.yaml /root/.dsh/profiles/web/pnpm-workspace.yaml
COPY dsh/cordis.patch.yml /root/.dsh/profiles/web/cordis.patch.yml
COPY dsh/settings.yaml /root/.dsh/settings.yaml
