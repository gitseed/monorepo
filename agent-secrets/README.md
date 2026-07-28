Read only secrets for AI agent consumption.

This repo is using the tofu-sensitive state bucket, because it has secrets, so agents can't plan against it.

`.infisical.json` contains the non-secret project binding used by
`infisical export`; it does not contain credentials.

Because we have the admin credentials from ouroboros, we can create many credentials automatically, but not all.

Manually created credentials:
* Github read only PAT: Github is literally the worst don't even get me started.
