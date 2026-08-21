#!/bin/bash
# Git identity is fetched from the GitHub API via gh — the credentials
# proxy injects the real GITHUB_TOKEN at runtime.

set -euo pipefail

aws_default_profile() {
    [[ -n ${AWS_ACCESS_KEY_ID:-} && -n ${AWS_SECRET_ACCESS_KEY:-} ]] || return 0

    echo "[default]"
    echo "aws_access_key_id = $AWS_ACCESS_KEY_ID"
    echo "aws_secret_access_key = $AWS_SECRET_ACCESS_KEY"
    if [[ -n ${AWS_SESSION_TOKEN:-} ]]; then echo "aws_session_token = $AWS_SESSION_TOKEN"; fi
    if [[ -n ${AWS_REGION:-} ]]; then echo "region = $AWS_REGION"; fi
    if [[ -n ${AWS_DEFAULT_REGION:-} && -z ${AWS_REGION:-} ]]; then echo "region = $AWS_DEFAULT_REGION"; fi
}

cloudflare_profile() {
    [[ -n ${CLOUDFLARE_ACCOUNT_ID:-} ]] || return 0

    cat <<EOF
[profile cloudflare]
aws_access_key_id = dummy-replaced-by-proxy
aws_secret_access_key = dummy-replaced-by-proxy
services = cloudflare

[services cloudflare]
s3 =
  endpoint_url = https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com
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
    local secret=/run/secrets/git_signing_key
    local ssh_dir="$HOME/.ssh"
    local key_file="$ssh_dir/signing_key"
    local signers_file="$ssh_dir/allowed_signers"

    # Fail loud: never fall back to unsigned commits.
    if [[ ! -s $secret ]]; then
        echo "entrypoint: git signing key not mounted at $secret -- refusing to start without commit signing" >&2
        return 1
    fi

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    # Copy the key with restrictive permissions (ssh-keygen rejects world-readable).
    cp "$secret" "$key_file"
    chmod 600 "$key_file"

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
