# Install Node 22+ and npm

## Why

The Cloudflare Worker app (`app/`) uses npm as its package manager and needs
Node 22+ for wrangler and the Worker runtime.

- `app/package.json` has devDependencies on `typescript` and `wrangler`
- `npm install` and `npx wrangler deploy` are the deploy steps
- `npm run tail` streams live logs

## Current state

The sandbox installs **Bun** (not Node/npm). Bun provides a `node` shim but
no `npm`. Veronica's `npm install` and `npx wrangler` commands need a real
Node + npm installation.

## What to do

Install Node 22+ via the official tarball (not Fedora's `nodejs` package,
which is older and pulls X11 deps). Add to `sandbox.containerfile`:

```dockerfile
ARG NODE_VERSION=v22.14.0
ARG NODE_SHA256=<verify at download time>
RUN curl -fsSL -o /tmp/node.tar.xz \
        "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-arm64.tar.xz" \
    && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum --check \
    && tar -C /usr/local --strip-components=1 -xJf /tmp/node.tar.xz \
    && rm -f /tmp/node.tar.xz
```

### Conflict with Bun

The sandbox currently symlinks `node` → `bun` (line 34 of the containerfile).
Installing real Node will shadow that symlink. Decision needed:

1. **Keep both** — install Node to `/usr/local/bin/node` (shadows Bun's
   symlink), keep `bun` as a separate command. OMP's `node` shim may break.
2. **Node for veronica, Bun for OMP** — install Node to a different prefix
   (e.g. `/opt/node`) and add to PATH only when working on veronica.

Option 1 is simpler and likely fine since real Node is a superset of Bun's
`node` shim for veronica's purposes.

## Acceptance

```bash
node --version  # prints v22.x
npm --version
cd /workspace/veronica/app && npm install && npx tsc --noEmit
```
