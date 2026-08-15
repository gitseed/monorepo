#!/bin/bash
# human-sandbox/scripts/up.bash               # bash in the current AWS profile's env
# human-sandbox/scripts/up.bash emacs -nw     # explicit command
#
# A working environment is an AWS profile: each profile in ~/.aws/config
# carries an infisical_machine_identity_id key (and optionally an
# infisical_project_id), and the profile's AWS account maps to its own
# infisical org + project. Select the environment with AWS_PROFILE; its
# secrets are exposed directly into the sandbox (no credentials proxy —
# the occupant is a trusted human).
set -euo pipefail

# Everything lives inside main() so bash parses the whole file before running
# any of it. Bash otherwise reads scripts lazily by byte offset, and editing
# this file while a sandbox session is running causes bogus syntax errors when
# the session exits.
main() {
    # omp workspace is the monorepo root directory
    GIT_PROJECT_DIR=$(cd -- "$(dirname -- "$0")/../.." && pwd)
    cd "$GIT_PROJECT_DIR"

    # Render once so a pkl failure exits loudly under set -e, then feed each
    # compose call via process substitution -- no rendered file on disk.
    # --project-directory makes relative build.context paths resolve from
    # human-sandbox/, not /dev/fd/. Exported for the infisical-spawned subshells.
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
            echo "WARNING: compose down failed -- the session container may still" >&2
            echo "         be running with credentials in its environment. Reap by label:" >&2
            echo "         docker ps -q --filter label=com.docker.compose.project=$PROJECT | xargs -r docker rm -f" >&2
            status=1
        fi
        return $status
    }
    trap cleanup EXIT

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

    # No build-time secrets (no CA to bake in — there is no MITM proxy), so
    # the build runs outside infisical.
    if built_recently human-sandbox; then
        compose -p "$PROJECT" build human-sandbox
    else
        compose -p "$PROJECT" build --pull --no-cache human-sandbox
    fi

    # Infisical auth derives from the AWS profile: each profile in ~/.aws/config
    # carries an infisical_machine_identity_id key, and aws-iam login exchanges
    # the SSO session for a token. INFISICAL_TOKEN makes every infisical run
    # below ignore whatever org the stored `infisical login` session selected.
    INFISICAL_MACHINE_IDENTITY_ID=$(aws configure get infisical_machine_identity_id)
    INFISICAL_TOKEN=$(infisical login --method=aws-iam --machine-identity-id "$INFISICAL_MACHINE_IDENTITY_ID" --plain --silent)
    export INFISICAL_TOKEN
    # Machine identity auth doesn't fall back to .infisical.json for the
    # project. Each profile may carry its own infisical_project_id for its
    # org; otherwise fall back to the repo's .infisical.json.
    INFISICAL_PROJECT_ID=$(aws configure get infisical_project_id)
    if [[ -z $INFISICAL_PROJECT_ID ]]; then
        INFISICAL_PROJECT_ID=$(jq -r .workspaceId .infisical.json)
    fi
    export INFISICAL_PROJECT_ID

    if [[ $# -eq 0 ]]; then
        set -- bash
    fi

    # The run must be under infisical so envs are populated
    if [[ -t 0 && -t 1 ]]; then
        infisical run -- bash -c 'compose "$@"' _ -p "$PROJECT" run --rm human-sandbox "$@"
    else
        infisical run -- bash -c 'compose "$@"' _ -p "$PROJECT" run --rm -T human-sandbox "$@"
    fi
}

main "$@"
