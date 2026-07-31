#!/bin/sh
# Sandbox init: route openrouter.ai to the credential-injecting envoy proxy.
# The runner discovers the proxy container's address and passes it as
# OPENROUTER_PROXY_IP; hosts(5) beats DNS for every process in the sandbox,
# so stock clients can use https://openrouter.ai unchanged.
set -e

if [ -n "${OPENROUTER_PROXY_IP:-}" ]; then
    # Remove any stale entry first so repeats never accumulate.
    sed -i '/[[:space:]]openrouter\.ai$/d' /etc/hosts
    echo "$OPENROUTER_PROXY_IP openrouter.ai" >> /etc/hosts
else
    echo "warning: OPENROUTER_PROXY_IP not set; openrouter.ai will resolve to the real host" >&2
fi

# The workdir is usually a host mount owned by a different uid.
git config --global --add safe.directory /workspace 2>/dev/null || true

exec "$@"
