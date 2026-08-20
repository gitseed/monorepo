#!/bin/bash
# ai-sandbox/scripts/up.sh      # interactive omp
# ai-sandbox/scripts/up.sh bash # plain shell instead
set -euo pipefail

# Everything lives inside main() so bash parses the whole file before running
# any of it. Bash otherwise reads scripts lazily by byte offset, and editing
# this file while a sandbox session is running causes bogus syntax errors when
# the session exits.
main() {
    GIT_PROJECT_DIR=$(cd -- "$(dirname -- "$0")/../.." && pwd)
    cd "$GIT_PROJECT_DIR"

    # Render once so a pkl failure exits loudly under set -e, then feed each
    # compose call via process substitution -- no rendered file on disk.
    # --project-directory makes relative build.context paths resolve from
    # ai-sandbox/, not /dev/fd/. Exported for the infisical-spawned subshells.
    COMPOSE_CONFIG=$(pkl eval --format yaml ai-sandbox/compose.pkl)
    export COMPOSE_CONFIG
    compose() {
        docker compose --project-directory ai-sandbox \
            -f <(printf '%s\n' "$COMPOSE_CONFIG") "$@"
    }
    export -f compose

    PROJECT=ai-sandbox-$$
    export GIT_PROJECT_DIR
    # Rendered into compose config (ai-sandbox dns:, dnsmasq --address); the
    # real values are discovered once each container is up. Exported empty
    # up front so compose invocations before then (builds, service ups)
    # don't warn about unset variables.
    export DNSMASQ_IP=
    export PROXY_IP=

    MEMORY_COMPOSE=(docker compose -f ai-sandbox/memory.compose.yml)
    # No secrets needed: postgres is socket-only with trust auth, shared with
    # sandbox sessions via the omp-memory-socket volume.
    echo "starting agent memory service..."
    "${MEMORY_COMPOSE[@]}" up -d --wait

    cleanup() {
        local status=$?
        if ! compose -p "$PROJECT" down --timeout 3 2>&1; then
            echo "WARNING: compose down failed -- the session proxy may still be running with injected credentials. Reap by label:" >&2
            echo "         docker ps -q --filter label=com.docker.compose.project=$PROJECT | xargs -r docker rm -f" >&2
            status=1
        fi

        local projects
        if ! projects=$(docker ps --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null); then
            echo "WARNING: could not enumerate containers; leaving memory service running" >&2
            return $status
        fi
        if printf '%s\n' "$projects" | grep -q '^ai-sandbox-[0-9][0-9]*$'; then
            return $status
        fi
        "${MEMORY_COMPOSE[@]}" down --timeout 10 2>/dev/null || true
        return $status
    }
    trap cleanup EXIT

    # Rebuild at least every 12 hours to update harness version.
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

    if built_recently credentials-proxy; then
        compose -p "$PROJECT" build proxy
    else
        compose -p "$PROJECT" build --pull --no-cache proxy
    fi

    # Infisical auth derives from the AWS profile: each profile in ~/.aws/config
    # carries an infisical_machine_identity_id key, and aws-iam login exchanges
    # the SSO session for a token. INFISICAL_TOKEN makes every infisical run
    # below ignore whatever org the stored `infisical login` session selected.
    # || true because a missing key exits 1 with no output, which set -e
    # would otherwise turn into a silent death before the guard below.
    #
    # aws configure set can't be suggested unconditionally: for the default
    # profile it always writes [default], even when the config uses
    # [profile default], and once both sections exist the CLI prefers
    # [default] and the profile's other settings vanish. Only named profiles
    # round-trip, so point default-profile users at the file itself.
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
    # The infisical project comes from the AWS profile too, same as the
    # machine identity. Resolved by slug within the logged-in org: slugs are
    # fixed by tofu (ouroboros/tofu, agent-secrets/tofu) and stable across
    # orgs, so no project IDs are stored anywhere. The machine identity token
    # is accepted by GET /api/v1/projects.
    INFISICAL_PROJECT_SLUG=$(aws configure get infisical_ai_project_slug || true)
    if [[ -z $INFISICAL_PROJECT_SLUG ]]; then
        echo "ERROR: AWS profile '${AWS_PROFILE:-default}' has no infisical_ai_project_slug key. Set it to the project to pull from, e.g.:" >&2
        profile_key_hint infisical_ai_project_slug agent
        exit 1
    fi
    INFISICAL_PROJECT_ID=$(
        # @file keeps the bearer token off curl's argv, which is world-readable.
        curl -fsS -H @<(printf 'Authorization: Bearer %s' "$INFISICAL_TOKEN") \
            "${INFISICAL_DOMAIN:-https://app.infisical.com}/api/v1/projects" \
        | jq -r --arg slug "$INFISICAL_PROJECT_SLUG" '.projects[] | select(.slug == $slug) | .id'
    )
    if [[ -z $INFISICAL_PROJECT_ID ]]; then
        echo "ERROR: no infisical project with slug '$INFISICAL_PROJECT_SLUG' visible to this machine identity" >&2
        exit 1
    fi
    export INFISICAL_PROJECT_ID

    if built_recently ai-sandbox; then
        infisical run --env=global -- bash -c 'compose "$@"' _ -p "$PROJECT" build ai-sandbox
    else
        infisical run --env=global -- bash -c 'compose "$@"' _ -p "$PROJECT" build --pull --no-cache ai-sandbox
    fi

    echo "starting credentials proxy..."
    infisical run --env=global -- bash -c 'compose "$@"' _ -p "$PROJECT" up -d --wait proxy

    # dnsmasq's --address=/amazonaws.com/... interpolates the proxy's IP
    # into its command at compose-invocation time, so discover it first.
    PROXY_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
        "$(compose -p "$PROJECT" ps -q proxy)")
    export PROXY_IP

    echo "starting dnsmasq..."
    compose -p "$PROJECT" up -d --wait dnsmasq
    # The sandbox's dns: needs a literal IP at container-create time.
    # Docker's own IPAM gives each project network a collision-free subnet,
    # so discover the address it assigned instead of reserving one up front.
    DNSMASQ_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
        "$(compose -p "$PROJECT" ps -q dnsmasq)")
    export DNSMASQ_IP

    if [[ $# -eq 0 ]]; then
        set -- omp
    fi

    # The run must also be under infisical so envs are populated
    if [[ -t 0 && -t 1 ]]; then
        infisical run --env=global -- bash -c 'compose "$@"' _ -p "$PROJECT" run --rm ai-sandbox "$@"
    else
        infisical run --env=global -- bash -c 'compose "$@"' _ -p "$PROJECT" run --rm -T ai-sandbox "$@"
    fi
}

main "$@"
