#!/bin/bash
# Git identity is fetched from the GitHub API via gh — the credentials
# proxy injects the real GITHUB_TOKEN at runtime.

set -euo pipefail

main() {
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

main "$@"

exec "$@"
