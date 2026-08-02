#!/bin/bash
# Credential-proxy entrypoint: pre-envoy DNS guard.
#
# The sandbox reaches this proxy through LINK-SCOPED aliases (the
# sandbox service's `links:` in compose.yml): embedded DNS answers
# openrouter.ai / api.neuralwatt.com with this container's address only
# inside the linking container. From HERE those names must resolve to
# the real upstreams -- if they ever resolve to this container again
# (a network-wide `aliases:` entry reintroduced), envoy forwards to its
# own listener in a loop. Assert both properties and fail BEFORE envoy
# starts: the compose healthcheck is a bare TCP connect to :443 and
# envoy binds its listener regardless of cluster DNS health
# (wait_for_warm_on_init: false), so a broken resolver would otherwise
# surface as a HEALTHY container 503ing every request.
set -euo pipefail

# Every v4 address of this container (one per attached network), to
# prove upstream answers aren't us. uname -n, not hostname(1): not
# installed everywhere.
self=$(getent ahostsv4 "$(uname -n)" | awk '{print $1}' | sort -u || true)

for host in openrouter.ai api.neuralwatt.com; do
    upstream=$(getent ahostsv4 "$host" | awk 'NR==1{print $1}' || true)
    if [[ -z "$upstream" ]]; then
        echo "proxy-entrypoint: $host unresolvable" >&2
        exit 1
    fi
    if [[ -n "$self" ]] && grep -qxF "$upstream" <<<"$self"; then
        echo "proxy-entrypoint: $host resolves to THIS container ($upstream) -- network-wide alias loop" >&2
        exit 1
    fi
    echo "proxy-entrypoint: $host -> $upstream" >&2
done

exec /docker-entrypoint.sh "$@"
