---
name: tofu-architecture
description: Load before creating or restructuring any tofu project. Layer layout, the two state buckets, and which bucket a layer with secrets in state must use.
---

# Tofu architecture

Projects keep their infra in tofu folders ("layers") with R2-backed S3
state. There are two state buckets, both created by ouroboros:

- **`tofu`** — agent-readable, so sandbox agents can plan against it.
  Its state must NEVER contain a secret.
- **`tofu-sensitive`** — no agent read access. Any layer whose state
  would contain a secret uses this bucket. Agents can't plan or apply
  these layers; that's accepted. Leave them to the human and say so —
  don't work around it.

The test: if `tofu show -json` would reveal a credential, the layer is
sensitive. This includes provider-computed attributes
(`google_service_account_key.private_key`,
`cloudflare_account_token.value`) and data-source results, not just
values you wrote in config.

## Layers

As few layers as possible — one is the goal. The only routine reason
for a second is the secrets rule: secret-bearing resources go in a
sensitive layer, everything else stays in a regular one. Don't invent
layers for tidiness.

Single layer: `<project>/tofu/`. Multiple layers: numbered folders in
apply order, lightning-style:

```
<project>/tofu/00_secrets/   # bucket = tofu-sensitive
<project>/tofu/01_app/       # bucket = tofu
```

Wire layers together with stable identifiers (names, IDs in
workspaces.tf). Never `terraform_remote_state` across the sensitive
boundary — regular layers must stay plannable by agents.

## Backend

Every layer's tofu.tf, only `bucket` and the prefix varying:

```hcl
backend "s3" {
  profile                     = "cloudflare"
  bucket                      = "tofu" # or "tofu-sensitive"
  workspace_key_prefix        = "<project>"
  key                         = basename(abspath(path.module))
  use_lockfile                = true
  region                      = "auto"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  skip_s3_checksum            = true
  use_path_style              = true
}
```

## Workspaces

Never the default workspace. Each layer has a workspaces.tf mapping
workspace name → settings, selected by
`local.workspace = local.workspaces[tofu.workspace]`.
