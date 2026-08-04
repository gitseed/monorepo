# Wire Cloudflare R2 S3 backend for tofu state

## Why

OpenTofu uses an S3-compatible Cloudflare R2 bucket as its state backend.

From `tofu/tofu.tf`:
```hcl
backend "s3" {
    profile                     = "cloudflare"
    bucket                      = "tofu"
    workspace_key_prefix        = "veronica"
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

The `profile = "cloudflare"` means tofu reads credentials from the `cloudflare`
profile in `~/.aws/credentials` (or `AWS_*` env vars). The R2 bucket is named
`tofu` and is shared with the `lightning` project (same backend).

## What to do

### 1. Install AWS CLI (or configure credentials directly)

The sandbox needs an AWS credentials file with the `cloudflare` profile
pointing to R2's S3-compatible API.

```ini
# ~/.aws/credentials
[cloudflare]
aws_access_key_id = <R2_ACCESS_KEY>
aws_secret_access_key = <R2_SECRET_KEY>
```

```ini
# ~/.aws/config
[profile cloudflare]
endpoint_url = https://<R2_ACCOUNT_ID>.r2.cloudflarestorage.com
region = auto
```

### 2. Wire R2 credentials

The R2 access key and secret need to be available in the sandbox. Options:

#### Option A: Envoy proxy for R2 endpoint

If `*.r2.cloudflarestorage.com` needs to be proxied:

```pkl
new {
    host = "<account_id>.r2.cloudflarestorage.com"
    name = "r2"
    secret = "r2_access_key"
    env = "AWS_ACCESS_KEY_ID"
}
```

This is complex because S3 auth uses `Authorization: AWS4-HMAC-SHA256` with
a computed signature, not a simple Bearer token. The Envoy credential
injector only handles Bearer/Basic auth headers.

#### Option B: Direct credentials (recommended)

R2 credentials don't have the same security concern as API tokens since
they're scoped to a single bucket. Wire them as environment variables:

```dockerfile
ENV AWS_ACCESS_KEY_ID=dummy-replaced-by-proxy
ENV AWS_SECRET_ACCESS_KEY=dummy-replaced-by-proxy
```

And write the credentials file in `entrypoint.sh` or a first-run script,
reading from env vars passed through compose.

```yaml
# compose.yml sandbox service:
environment:
  - R2_ACCESS_KEY
  - R2_SECRET_KEY
```

```bash
# entrypoint.sh
mkdir -p ~/.aws
cat > ~/.aws/credentials <<EOF
[cloudflare]
aws_access_key_id = ${R2_ACCESS_KEY}
aws_secret_access_key = ${R2_SECRET_KEY}
EOF
cat > ~/.aws/config <<EOF
[profile cloudflare]
endpoint_url = https://<account_id>.r2.cloudflarestorage.com
region = auto
EOF
```

### 3. Add R2 secrets to Infisical

Add `r2_access_key` and `r2_secret_key` to the Infisical project.

## Notes

- The R2 endpoint URL uses the account ID, which is the same as
  `cloudflare_account_id` in `tofu/workspace.tf`:
  `287cae24e46a0aeed1dbc2942fc58dd7`.
- The `use_lockfile = true` setting means tofu uses S3-native locking (via
  DynamoDB-compatible R2 tables or the lockfile object). Verify R2 supports
  this.

## Acceptance

```bash
cd /workspace/veronica/tofu && tofu init
# State backend connection succeeds, providers download
```
