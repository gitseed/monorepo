#!/bin/bash
set -euo pipefail

main() {
    GIT_PROJECT_DIR=$(cd -- "$(dirname -- "$0")/../.." && pwd)
    cd "$GIT_PROJECT_DIR"

    COMPOSE_CONFIG=$(pkl eval --format yaml human-sandbox/compose.pkl)
    export COMPOSE_CONFIG
    compose() {
        docker compose --project-directory human-sandbox \
            -f <(printf '%s\n' "$COMPOSE_CONFIG") "$@"
    }
    export -f compose

    PROJECT=human-sandbox-$$
    export GIT_PROJECT_DIR

    cleanup() {
        local status=$?
        if ! compose -p "$PROJECT" down --timeout 3 2>&1; then
            echo "WARNING: compose down failed -- the session container may still be running with credentials in its environment. Reap by label:" >&2
            echo "         docker ps -q --filter label=com.docker.compose.project=$PROJECT | xargs -r docker rm -f" >&2
            status=1
        fi
        return $status
    }
    trap cleanup EXIT HUP INT TERM

    # Rebuild at least every 12 hours to pick up package/tool updates.
    built_recently() {
        local max_age=$(( 12 * 3600 ))
        local created
        if ! created=$(docker image inspect --format '{{.Created}}' "$1" 2>/dev/null); then
            return 1
        fi
        # Docker emits timestamps like 2026-08-06T00:03:08.922498832-05:00.
        # jq 1.7.1's fromdateiso8601 requires a literal Z suffix and rejects
        # fractional seconds and timezone offsets, so strip both and append Z.
        local created_epoch now_epoch
        created_epoch=$(jq -n --arg ts "$created" '
            $ts | sub("\\.\\d+"; "")
                | sub("([+-]\\d{2}:\\d{2})$"; "")
                | . + "Z"
                | fromdateiso8601 | floor
        ')
        now_epoch=$(date +%s)
        local age=$(( now_epoch - created_epoch ))
        (( age >= 0 && age < max_age ))
    }

    if built_recently human-sandbox; then
        compose -p "$PROJECT" build human-sandbox
    else
        compose -p "$PROJECT" build --pull --no-cache human-sandbox
    fi

    # Infisical auth derives from the AWS profile
    profile_key_hint() {
        if [[ -n ${AWS_PROFILE:-} && $AWS_PROFILE != default ]]; then
            echo "       aws configure set $1 $2 --profile $AWS_PROFILE" >&2
        else
            echo "       Add '$1 = $2' to your default profile's section in ~/.aws/config ([default], or [profile default] if your config uses that form)." >&2
        fi
    }
    INFISICAL_MACHINE_IDENTITY_ID=$(aws configure get infisical_machine_identity_id || true)
    if [[ -z $INFISICAL_MACHINE_IDENTITY_ID ]]; then
        echo "ERROR: AWS profile '${AWS_PROFILE:-default}' has no infisical_machine_identity_id key. Set it to the machine identity to log in as, e.g.:" >&2
        profile_key_hint infisical_machine_identity_id '<uuid>'
        exit 1
    fi
    if ! INFISICAL_TOKEN=$(infisical login --method=aws-iam --machine-identity-id "$INFISICAL_MACHINE_IDENTITY_ID" --plain --silent); then
        echo "ERROR: infisical machine identity login failed. It signs in with your AWS credentials (profile '${AWS_PROFILE:-default}'), so this usually means they are missing or expired -- an IMDS timeout (169.254.169.254) above is the AWS SDK finding no credentials at all. Re-auth with e.g. \`aws sso login${AWS_PROFILE:+ --profile $AWS_PROFILE}\`" >&2
        exit 1
    fi
    export INFISICAL_TOKEN
    export INFISICAL_MACHINE_IDENTITY_ID
    # The infisical project comes from the AWS profile too
    INFISICAL_PROJECT_SLUG=$(aws configure get infisical_human_project_slug || true)
    if [[ -z $INFISICAL_PROJECT_SLUG ]]; then
        echo "ERROR: AWS profile '${AWS_PROFILE:-default}' has no infisical_human_project_slug key. Set it to the project to pull from, e.g.:" >&2
        profile_key_hint infisical_human_project_slug ouroboros
        exit 1
    fi
    INFISICAL_PROJECT_ID=$(
        curl -fsS -H "Authorization: Bearer $INFISICAL_TOKEN" \
            "${INFISICAL_DOMAIN:-https://app.infisical.com}/api/v1/projects" \
        | jq -r --arg slug "$INFISICAL_PROJECT_SLUG" '.projects[] | select(.slug == $slug) | .id'
    )
    if [[ -z $INFISICAL_PROJECT_ID ]]; then
        echo "ERROR: no infisical project with slug '$INFISICAL_PROJECT_SLUG' visible to this machine identity" >&2
        exit 1
    fi
    export INFISICAL_PROJECT_ID

    # Credentials for the sandbox's default AWS profile.
    local creds
    if ! creds=$(aws configure export-credentials --profile "${AWS_PROFILE:-default}" --format process 2>&1); then
        echo "ERROR: exporting AWS credentials from profile '${AWS_PROFILE:-default}' failed:" >&2
        printf '%s\n' "$creds" >&2
        echo "       This usually means its SSO session expired — re-auth with \`aws sso login${AWS_PROFILE:+ --profile $AWS_PROFILE}\` and retry." >&2
        exit 1
    fi
    SANDBOX_AWS_ACCESS_KEY_ID=$(jq -r '.AccessKeyId // empty' <<< "$creds")
    SANDBOX_AWS_SECRET_ACCESS_KEY=$(jq -r '.SecretAccessKey // empty' <<< "$creds")
    SANDBOX_AWS_SESSION_TOKEN=$(jq -r '.SessionToken // empty' <<< "$creds")
    SANDBOX_AWS_REGION=$(aws configure get region || true)
    SANDBOX_AWS_OUTPUT=$(aws configure get output || true)
    export SANDBOX_AWS_ACCESS_KEY_ID SANDBOX_AWS_SECRET_ACCESS_KEY SANDBOX_AWS_SESSION_TOKEN
    export SANDBOX_AWS_REGION SANDBOX_AWS_OUTPUT

    if [[ $# -eq 0 ]]; then
        set -- bash
    fi

    # The run must be under infisical so envs are populated.
    if [[ -t 0 && -t 1 ]]; then
        infisical run --env=global -- bash -c 'compose "$@"' _ -p "$PROJECT" run --rm human-sandbox "$@"
    else
        infisical run --env=global -- bash -c 'compose "$@"' _ -p "$PROJECT" run --rm -T human-sandbox "$@"
    fi
}

main "$@"
