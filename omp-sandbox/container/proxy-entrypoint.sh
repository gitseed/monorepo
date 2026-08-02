#!/bin/bash
# Credential-proxy entrypoint: the upstream-resolution split.
#
# This container's compose network aliases (openrouter.ai,
# api.neuralwatt.com) ARE this container as far as docker's embedded DNS
# (127.0.0.11) is concerned -- resolving upstreams through it loops envoy
# back into itself. Envoy must instead resolve the REAL upstreams through
# the host resolver stack, WARP-transparently, without hardcoding an
# OrbStack-internal address.
#
# dockerd already publishes that endpoint in every container's generated
# /etc/resolv.conf:
#   # ExtServers: [host(0.250.250.200)]
# Parse it, point this container's resolver straight at it, and fail
# BEFORE envoy starts if anything is off: the compose healthcheck is a
# bare TCP connect to :443 and envoy starts listeners regardless of
# cluster DNS health (wait_for_warm_on_init: false), so a dead resolver
# would otherwise surface as a HEALTHY container 503ing every request.
set -euo pipefail

RESOLV=/etc/resolv.conf

# BRE backslash-parens bugged here once (unopened group under every sed)
# -- ERE, anchored, first-entry-only, so multiple ExtServers entries
# parse deterministically.
ext=$(sed -nE 's/^# ExtServers: \[host\(([0-9a-fA-F.:]+)\).*/\1/p' "$RESOLV" | head -1)
if [[ -z "$ext" ]]; then
    echo "proxy-entrypoint: no '# ExtServers: [host(<ip>)]' comment in $RESOLV" >&2
    exit 1
fi

# Capture our own address while embedded DNS still answers (used below to
# prove we escaped the alias). uname -n, not hostname(1): not installed
# everywhere.
self=$(getent ahostsv4 "$(uname -n)" | awk 'NR==1{print $1}' || true)

# In-place truncating write: the file is a per-container bind mount --
# rename-over (sed -i) is refused, direct writes are honored by
# getaddrinfo.
printf 'nameserver %s\noptions ndots:0\n' "$ext" > "$RESOLV"

upstream=$(getent ahostsv4 openrouter.ai | awk 'NR==1{print $1}')
if [[ -z "$upstream" ]]; then
    echo "proxy-entrypoint: openrouter.ai unresolvable via $ext" >&2
    exit 1
fi
if [[ -n "$self" && "$upstream" == "$self" ]]; then
    echo "proxy-entrypoint: openrouter.ai still resolves to THIS container ($self) -- alias loop not escaped" >&2
    exit 1
fi

echo "proxy-entrypoint: upstream DNS via $ext; openrouter.ai -> $upstream" >&2
exec /docker-entrypoint.sh "$@"
