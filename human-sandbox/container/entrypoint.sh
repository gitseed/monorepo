#!/bin/bash
# Entrypoint: set up git identity, https push credentials, SSH commit
# signing, and ~/.aws/config before handing off to the main process.
# Each block keys off its own env var being present (human sandboxes
# expose secrets directly); missing secrets skip the block, not fail the
# start. Unlike ai-sandbox there is no proxy injecting anything.

set -euo pipefail

# Default AWS profile from the credentials scripts/up.bash resolved on the
# host (aws configure export-credentials).
aws_default_profile() {
    [[ -n ${SANDBOX_AWS_ACCESS_KEY_ID:-} && -n ${SANDBOX_AWS_SECRET_ACCESS_KEY:-} ]] || return 0

    echo "[default]"
    echo "aws_access_key_id = $SANDBOX_AWS_ACCESS_KEY_ID"
    echo "aws_secret_access_key = $SANDBOX_AWS_SECRET_ACCESS_KEY"
    if [[ -n ${SANDBOX_AWS_SESSION_TOKEN:-} ]]; then echo "aws_session_token = $SANDBOX_AWS_SESSION_TOKEN"; fi
    if [[ -n ${SANDBOX_AWS_REGION:-} ]]; then echo "region = $SANDBOX_AWS_REGION"; fi
    if [[ -n ${SANDBOX_AWS_OUTPUT:-} ]]; then echo "output = $SANDBOX_AWS_OUTPUT"; fi
}

# AWS config for tofu's s3-on-R2 state backend (profile "cloudflare" in any
# tofu.tf). R2 S3-compatible creds are *derived* from the Cloudflare API
# token, not supplied separately:
#   Access Key ID     = token id (from /user/tokens/verify)
#   Secret Access Key = SHA-256 of the token value
# Source: https://developers.cloudflare.com/r2/api/tokens/
#         #get-s3-api-credentials-from-an-api-token
cloudflare_profile() {
    [[ -n ${CLOUDFLARE_API_TOKEN:-} ]] || return 0

    local api=https://api.cloudflare.com/client/v4
    local token_id account_id
    token_id=$(curl -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "$api/user/tokens/verify" | jq -er '.result.id')

    # The account that owns the state buckets. Tokens often see several
    # accounts, so take it from the project's CLOUDFLARE_ACCOUNT_ID; only
    # fall back to the sole visible account.
    local accounts
    accounts=$(curl -fsS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "$api/accounts")
    if [[ -n ${CLOUDFLARE_ACCOUNT_ID:-} ]]; then
        account_id=$(jq -er --arg id "$CLOUDFLARE_ACCOUNT_ID" \
            '.result[] | select(.id == $id) | .id' <<< "$accounts") \
            || { echo "entrypoint: CLOUDFLARE_ACCOUNT_ID=$CLOUDFLARE_ACCOUNT_ID not visible to this token" >&2; return 1; }
    else
        account_id=$(jq -er 'if (.result | length) == 1 then .result[0].id else empty end' <<< "$accounts") \
            || { echo "entrypoint: token sees multiple cloudflare accounts; add CLOUDFLARE_ACCOUNT_ID to the infisical project" >&2; return 1; }
    fi

    # Same shape as the aws config the ouroboros tofu once generated.
    cat <<EOF
[profile cloudflare]
aws_access_key_id=${token_id}
aws_secret_access_key=$(printf '%s' "$CLOUDFLARE_API_TOKEN" | sha256sum | cut -d' ' -f1)
services = cloudflare

[services cloudflare]
s3 =
  endpoint_url = https://${account_id}.r2.cloudflarestorage.com
EOF
}

aws_config() {
    local default_part cloudflare_part
    default_part=$(aws_default_profile)
    cloudflare_part=$(cloudflare_profile)
    if [[ -z $default_part && -z $cloudflare_part ]]; then
        return 0
    fi

    local aws_dir="$HOME/.aws"
    mkdir -p "$aws_dir"
    chmod 700 "$aws_dir"

    {
        if [[ -n $default_part ]]; then printf '%s\n' "$default_part"; fi
        if [[ -n $default_part && -n $cloudflare_part ]]; then echo; fi
        if [[ -n $cloudflare_part ]]; then printf '%s\n' "$cloudflare_part"; fi
    } > "$aws_dir/config"
    chmod 600 "$aws_dir/config"
}

git_config() {
    # No token — skip git setup entirely.
    [[ -n ${GITHUB_TOKEN:-} ]] || return 0

    # https git credentials via gh's credential helper (replaces
    # ai-sandbox's proxy-injected GITHUB_TOKEN_BASIC).
    gh auth setup-git

    local git_name git_email
    git_name=$(gh api user --jq '.login')
    git_email=$(gh api user/emails --jq '.[] | select(.primary==true) | .email')

    git config --global user.name "$git_name"
    git config --global user.email "$git_email"

    # SSH commit signing, when the key is provided (plain env passthrough;
    # absent key means unsigned commits, not a failed start).
    [[ -n ${GIT_SIGNING_KEY:-} ]] || return 0

    local ssh_dir="$HOME/.ssh"
    local key_file="$ssh_dir/signing_key"
    local signers_file="$ssh_dir/allowed_signers"

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Write the key with restrictive permissions (ssh-keygen rejects world-readable).
    printf '%s\n' "$GIT_SIGNING_KEY" > "$key_file"
    chmod 600 "$key_file"

    git config --global commit.gpgsign true
    git config --global gpg.format ssh
    git config --global user.signingkey "$key_file"
    git config --global gpg.ssh.program ssh-keygen
    git config --global gpg.ssh.allowedSignersFile "$signers_file"

    # Derive the public key and create the allowed_signers file for verification.
    local pubkey
    pubkey=$(ssh-keygen -y -f "$key_file")
    echo "$git_email $pubkey" > "$signers_file"
    chmod 600 "$signers_file"
}

main() {
    aws_config
    git_config
}

main "$@"

exec "$@"
