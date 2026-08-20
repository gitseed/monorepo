#!/bin/bash
# Entrypoint: set up the default AWS profile and git SSH commit signing
# before handing off to the main process (omp). The AWS profile is mined
# from the host's selected AWS profile by scripts/up.bash; the signing key
# is mounted at /run/secrets/git_signing_key by compose. Git identity
# (name, email) is fetched dynamically from the GitHub API via gh, since
# the proxy injects the real GITHUB_TOKEN at runtime.

set -euo pipefail

# Default AWS profile mirroring the host profile's SSO settings, so
# `aws sso login` works inside the sandbox: with no browser available the
# CLI prints the authorization URL and code for the user to open elsewhere.
# Session-form config when the host profile references an sso-session,
# legacy inline keys otherwise. Missing values arrive as empty env vars
# and their lines are skipped; without the minimum (start URL + region)
# there is nothing `aws sso login` could do, so skip the file entirely.
aws_sso_config() {
    [[ -n ${AWS_SSO_START_URL:-} && -n ${AWS_SSO_REGION:-} ]] || return 0

    local aws_dir="$HOME/.aws"
    mkdir -p "$aws_dir"
    chmod 700 "$aws_dir"

    {
        echo "[default]"
        if [[ -n ${AWS_SSO_SESSION:-} ]]; then
            echo "sso_session = $AWS_SSO_SESSION"
        else
            echo "sso_start_url = $AWS_SSO_START_URL"
            echo "sso_region = $AWS_SSO_REGION"
        fi
        if [[ -n ${AWS_SSO_ACCOUNT_ID:-} ]]; then echo "sso_account_id = $AWS_SSO_ACCOUNT_ID"; fi
        if [[ -n ${AWS_SSO_ROLE_NAME:-} ]]; then echo "sso_role_name = $AWS_SSO_ROLE_NAME"; fi
        if [[ -n ${AWS_PROFILE_REGION:-} ]]; then echo "region = $AWS_PROFILE_REGION"; fi
        if [[ -n ${AWS_PROFILE_OUTPUT:-} ]]; then echo "output = $AWS_PROFILE_OUTPUT"; fi
        if [[ -n ${AWS_SSO_SESSION:-} ]]; then
            echo
            echo "[sso-session $AWS_SSO_SESSION]"
            echo "sso_start_url = $AWS_SSO_START_URL"
            echo "sso_region = $AWS_SSO_REGION"
            if [[ -n ${AWS_SSO_REGISTRATION_SCOPES:-} ]]; then
                echo "sso_registration_scopes = $AWS_SSO_REGISTRATION_SCOPES"
            fi
        fi
    } > "$aws_dir/config"
    chmod 600 "$aws_dir/config"
}

main() {
    aws_sso_config

    local secret=/run/secrets/git_signing_key
    local ssh_dir="$HOME/.ssh"
    local key_file="$ssh_dir/signing_key"
    local signers_file="$ssh_dir/allowed_signers"

    # No secret mounted — nothing to do.
    [[ -f $secret ]] || return 0

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Copy the key with restrictive permissions (ssh-keygen rejects world-readable).
    cp "$secret" "$key_file"
    chmod 600 "$key_file"

    # Fetch git identity from GitHub API (proxy injects real token at runtime).
    local git_name git_email pubkey
    git_name=$(gh api user --jq '.login')
    git_email=$(gh api user/emails --jq '.[] | select(.primary==true) | .email')

    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    git config --global commit.gpgsign true
    git config --global gpg.format ssh
    git config --global user.signingkey "$key_file"
    git config --global gpg.ssh.program ssh-keygen
    git config --global gpg.ssh.allowedSignersFile "$signers_file"

    # Derive the public key and create the allowed_signers file for verification.
    pubkey=$(ssh-keygen -y -f "$key_file")
    echo "$git_email $pubkey" > "$signers_file"
    chmod 600 "$signers_file"
}

main "$@"

exec "$@"
