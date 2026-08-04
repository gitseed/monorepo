# Install Google Cloud CLI

## Why

The tofu apply triggers Cloud Build (`gcloud builds submit`) to build the
driver image into Artifact Registry. The Google provider also needs
application-default credentials for the project.

- `gcloud builds submit` — builds driver image remotely
- `gcloud auth login` + `gcloud auth application-default login` — for the
  Google provider in tofu
- Project ID: `untrusted-agent` (from `tofu/workspace.tf`)

## What to do

Install the gcloud CLI in `sandbox.containerfile`. The official method is
the archive download (not a Fedora package):

```dockerfile
ARG GCLOUD_VERSION=521.0.0
ARG GCLOUD_SHA256=<verify at download time>
RUN curl -fsSL -o /tmp/gcloud.tar.gz \
        "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-arm64.tar.gz" \
    && echo "${GCLOUD_SHA256}  /tmp/gcloud.tar.gz" | sha256sum --check \
    && tar -C /usr/local -xzf /tmp/gcloud.tar.gz \
    && /usr/local/google-cloud-cli/install.sh --quiet \
    && rm -f /tmp/gcloud.tar.gz
ENV PATH="/usr/local/google-cloud-cli/bin:${PATH}"
```

## Authentication

Gcloud credentials need to be established after container start. Two options:

1. **Service account key** — store a JSON key as a secret, run
  `gcloud auth activate-service-account --key-file=...` at startup.
  Suitable for automated tofu applies from the sandbox.

2. **User login** — `gcloud auth login` and `gcloud auth application-default
  login` interactively after container start. Suitable for development.

The credential wiring is tracked in
[`08-credential-gcloud.md`](08-credential-gcloud.md).

## Acceptance

```bash
gcloud --version
gcloud auth list  # shows an active account
gcloud auth application-default print-access-token  # succeeds
```
