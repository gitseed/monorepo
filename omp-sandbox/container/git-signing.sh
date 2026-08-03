#!/bin/bash
# Profile script: set up git SSH commit signing from Docker runtime secret.
# The private key is mounted at /run/secrets/git_signing_key by compose.
# Git identity (name, email) is fetched dynamically from the GitHub API
# via gh, since the proxy injects the real GITHUB_TOKEN at runtime.

set -euo pipefail

SECRET=/run/secrets/git_signing_key
SSH_DIR="$HOME/.ssh"
KEY_FILE="$SSH_DIR/signing_key"
SIGNERS_FILE="$SSH_DIR/allowed_signers"

if [[ ! -f $SECRET ]]; then
    return 0 2>/dev/null || true
fi

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Copy the key with restrictive permissions.
cp "$SECRET" "$KEY_FILE"
chmod 600 "$KEY_FILE"

# Fetch git identity from GitHub API (proxy injects real token at runtime).
GIT_NAME=$(gh api user --jq '.login')
GIT_EMAIL=$(gh api user/emails --jq '.[] | select(.primary==true) | .email')

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global commit.gpgsign true
git config --global gpg.format ssh
git config --global user.signingkey "$KEY_FILE"
git config --global gpg.ssh.program ssh-keygen
git config --global gpg.ssh.allowedSignersFile "$SIGNERS_FILE"

# Derive the public key and create the allowed_signers file for verification.
pubkey=$(ssh-keygen -y -f "$KEY_FILE")
echo "$GIT_EMAIL $pubkey" > "$SIGNERS_FILE"
chmod 600 "$SIGNERS_FILE"
