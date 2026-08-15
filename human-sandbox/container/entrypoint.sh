#!/bin/bash
# Entrypoint: set up git identity, https push credentials, and SSH commit
# signing before handing off to the main process. Everything keys off
# GITHUB_TOKEN being present in the environment (human sandboxes expose
# secrets directly); without it the sandbox still starts, just without
# git setup. Unlike ai-sandbox there is no proxy injecting anything.

set -euo pipefail

main() {
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

main "$@"

exec "$@"
