# human-sandbox

Sandboxed working environments in [orbstack](https://orbstack.dev/) for humans. Sibling of [ai-sandbox](../ai-sandbox/README.md) with the trust model inverted: the occupant is a trusted human, so there is no credentials proxy, no env-var masking, and no DNS interception — secrets from [infisical](https://infisical.com/) are exposed directly into the sandbox environment.

## Working environments

An environment is an AWS profile. Each profile in `~/.aws/config` carries:

- `infisical_machine_identity_id` — machine identity for that account's infisical org (same key `ai-sandbox/scripts/up.bash` reads)
- `infisical_project_id` — infisical project in that org; when unset, falls back to the repo's `.infisical.json`

The profile's AWS account connects to its own infisical org + project, so switching `AWS_PROFILE` switches which secrets populate the sandbox.

## Usage

```console
$ human-sandbox/scripts/up.bash                      # bash in the current AWS_PROFILE's environment
$ AWS_PROFILE=work human-sandbox/scripts/up.bash     # the 'work' environment
$ AWS_PROFILE=work human-sandbox/scripts/up.bash emacs -nw
```

The monorepo is mounted at `/workspace`; git commit signing is set up from the `GIT_SIGNING_KEY` secret (mounted as a compose secret, never written to the image). Sessions are ephemeral like ai-sandbox: the container is destroyed on exit (`run --rm` + compose down), and the image rebuilds at least every 12 hours.

Secrets live only in the container's environment and tmpfs secret mounts — never on disk.
