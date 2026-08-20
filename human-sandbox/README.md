# human-sandbox

A orbstack sandbox that should have all the credentials and tools you need to work.

The entrypoint writes a `default` AWS profile to `~/.aws/config`: credentials resolved on the host by `aws configure export-credentials`, plus the profile's `infisical_machine_identity_id` so `infisical login --method=aws-iam` works inside.
