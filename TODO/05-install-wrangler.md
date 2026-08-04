# Install Cloudflare Wrangler

## Why

Wrangler is the Cloudflare Workers CLI used to deploy the Worker and manage
secrets.

- `npx wrangler deploy` — deploys the Worker + container
- `npx wrangler secret put OPENAI_API_KEY` — uploads Worker secret
- `npx wrangler secret put OPENAI_WEBHOOK_SECRET` — uploads Worker secret
- `npm run tail` — streams live logs (`wrangler tail`)

## What to do

Wrangler is installed as an npm devDependency in `app/package.json`
(`"wrangler": "^4.112.0"`), so `npm install` in the `app/` directory
installs it locally. No global install needed.

### Prerequisite

This depends on
[`02-install-node-npm.md`](02-install-node-npm.md) — npm must be available
for `npm install` to work.

### Optional: global install

If you want `wrangler` available without `npx`:

```dockerfile
RUN npm install -g wrangler@^4
```

But `npx wrangler` from the project's own devDependency is preferred to
avoid version drift.

## Acceptance

```bash
cd /workspace/veronica/app && npm install && npx wrangler --version
```
