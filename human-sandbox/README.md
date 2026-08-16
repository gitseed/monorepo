# human-sandbox

Sandboxed working environments in [orbstack](https://orbstack.dev/) for humans. Sibling of [ai-sandbox](../ai-sandbox/README.md) with the trust model inverted: the occupant is a trusted human, so there is no credentials proxy, no env-var masking, and no DNS interception — secrets from [infisical](https://infisical.com/) are exposed directly into the sandbox environment.

## Working environments

An environment is an AWS profile. Each profile in `~/.aws/config` carries an `infisical_machine_identity_id` (same key `ai-sandbox/scripts/up.bash` reads); the profile's AWS account maps to its own infisical org. The profile also names the infisical project to pull from via `infisical_human_project_slug` — `ouroboros` for human admin credentials (the agent sandbox reads its own project from `infisical_ai_project_slug`). `up.bash` resolves the slug to a project ID within the logged-in org via `GET /api/v1/projects`, so no project IDs are stored anywhere. `INFISICAL_DOMAIN` overrides the API host (default `https://app.infisical.com`).

```console
$ aws configure set infisical_machine_identity_id <id>
$ aws configure set infisical_human_project_slug ouroboros
```

## Usage

```console
$ human-sandbox/scripts/up.bash                      # bash in the current AWS_PROFILE's environment
$ AWS_PROFILE=work human-sandbox/scripts/up.bash     # the 'work' environment
$ AWS_PROFILE=work human-sandbox/scripts/up.bash emacs -nw
```

The monorepo is mounted at `/workspace`. Git identity and https push credentials come from `GITHUB_TOKEN` (gh's credential helper); SSH commit signing is set up when `GIT_SIGNING_KEY` is present in the project — both plain environment passthroughs. Sessions are ephemeral like ai-sandbox: the container is destroyed on exit (`run --rm` + compose down), and the image rebuilds at least every 12 hours.

The sandbox stays isolated to its environment: no host `~/.aws` inside. Instead the entrypoint derives the aws `cloudflare` profile that tofu's s3 state backend needs from the project's `CLOUDFLARE_API_TOKEN` (R2 S3 creds are the token id and the sha256 of its value, per the [cloudflare docs](https://developers.cloudflare.com/r2/api/tokens/#get-s3-api-credentials-from-an-api-token)), pinned to the right account by `CLOUDFLARE_ACCOUNT_ID`. `tofu` is installed and `TF_DATA_DIR` is `.sandbox_tofu`: provider downloads stay separate from the host's `.terraform` (darwin binaries the container can't run) and persist across sessions on the mounted workspace.

Secrets flow one way — into the container's environment. Nothing writes credentials back to host disk.
