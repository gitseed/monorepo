#!/bin/bash
# Profile script: set up git SSH commit signing from Docker runtime secret.
# The private key is mounted at /run/secrets/git_signing_key by compose.
# We copy it to ~/.ssh with 600 permissions (ssh-keygen rejects world-readable keys)
# and derive the public key for the allowed_signers file (used by git verify-commit).

set -euo pipefail

SECRET=/run/secrets/git_signing_key
SSH_DIR="$HOME/.ssh"
KEY_FILE="$SSH_DIR/signing_key"
SIGNERS_FILE="$SSH_DIR/allowed_signers"
GIT_EMAIL="paulcdejean+gitseedagent@gmail.com"

if [[ ! -f $SECRET ]]; then
    return 0 2>/dev/null || true
fi

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Copy the key with restrictive permissions.
cp "$SECRET" "$KEY_FILE"
chmod 600 "$KEY_FILE"

# Derive the public key and create the allowed_signers file for verification.
pubkey=$(ssh-keygen -y -f "$KEY_FILE")
echo "$GIT_EMAIL $pubkey" > "$SIGNERS_FILE"
chmod 600 "$SIGNERS_FILE"
