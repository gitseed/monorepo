#!/bin/bash
set -euo pipefail

if [[ -n ${R2_ACCESS_KEY_ID:-} && -n ${R2_SECRET_ACCESS_KEY:-} ]]; then
    export R2_CREDENTIALS_FILE_CONTENT=$(printf '[default]\naws_access_key_id = %s\naws_secret_access_key = %s\n' \
        "$R2_ACCESS_KEY_ID" "$R2_SECRET_ACCESS_KEY")
fi

exec /docker-entrypoint.sh "$@"
