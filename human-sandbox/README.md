# human-sandbox

Sandboxed working environments in [orbstack](https://orbstack.dev/) for humans. Sibling of [ai-sandbox](../ai-sandbox/README.md) with the trust model inverted: the occupant is a trusted human, so there is no credentials proxy, no env-var masking, and no DNS interception — secrets from [infisical](https://infisical.com/) are exposed directly into the sandbox environment.

## Working environments

An environment is an AWS profile. Each profile in `~/.aws/config` carries an `infisical_machine_identity_id` (same key `ai-sandbox/scripts/up.bash` reads); the profile's AWS account maps to its own infisical org. Within the logged-in org, `up.bash` resolves this sandbox's project by slug — `ouroboros`, the human admin credentials project, where the agent sandbox uses `agent` instead — via `GET /api/v1/projects`, so no project IDs are stored anywhere. `INFISICAL_DOMAIN` overrides the API host (default `https://app.infisical.com`).

## Usage

```console
$ human-sandbox/scripts/up.bash                      # bash in the current AWS_PROFILE's environment
$ AWS_PROFILE=work human-sandbox/scripts/up.bash     # the 'work' environment
$ AWS_PROFILE=work human-sandbox/scripts/up.bash emacs -nw
```

The monorepo is mounted at `/workspace`; git commit signing is set up from the `GIT_SIGNING_KEY` secret (mounted as a compose secret, never written to the image). Sessions are ephemeral like ai-sandbox: the container is destroyed on exit (`run --rm` + compose down), and the image rebuilds at least every 12 hours.

Secrets live only in the container's environment and tmpfs secret mounts — never on disk.
