# Install OpenTofu 1.12.3

## Why

Veronica's infrastructure lives in `tofu/` and is managed with OpenTofu.
The `required_version` is pinned to `1.12.3`.

- `tofu init`, `tofu workspace select veronica`, `tofu apply`
- `tofu output -raw <key>` for reading outputs

## What to do

Add to `sandbox.containerfile`:

```dockerfile
ARG TOFU_VERSION=1.12.3
ARG TOFU_SHA256=<verify at download time>
RUN curl -fsSL -o /tmp/tofu.zip \
        "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/opentofu_${TOFU_VERSION}_linux_arm64.zip" \
    && echo "${TOFU_SHA256}  /tmp/tofu.zip" | sha256sum --check \
    && unzip /tmp/tofu.zip -d /usr/local/bin tofu \
    && chmod 0755 /usr/local/bin/tofu \
    && rm -f /tmp/tofu.zip
```

## Notes

- Terraform is NOT a substitute — the repo pins OpenTofu specifically
  (different provider ecosystem, backend lockfile format).
- The `.terraform.lock.hcl` is committed; `tofu init` will verify provider
  hashes against it.
- The backend is S3-compatible Cloudflare R2 (see
  [`10-credential-r2-backend.md`](10-credential-r2-backend.md)).

## Acceptance

```bash
tofu version  # prints OpenTofu v1.12.3
cd /workspace/veronica/tofu && tofu init
```
