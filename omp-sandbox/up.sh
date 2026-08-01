#!/bin/bash
# Brings the omp sandbox boundary up from cold and runs a sandbox:
#
#   ./up.sh                   # ensure images + proxy, then interactive omp
#   ./up.sh --build           # same, but force-rebuild the sandbox image
#                             # (needed after a cert rotation: secret mounts
#                             # never bust the build cache)
#   ./up.sh bash              # any args after options go to run.sh
#
# Idempotent: safe to run repeatedly.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=0
if [[ "${1:-}" == "--build" || "${1:-}" == "-b" ]]; then
    BUILD=1
    shift
fi

# Dependency 1: the proxy image, then the proxy itself (idempotent start).
if ! container image inspect credentials-proxy >/dev/null 2>&1; then
    ./credentials-proxy/build.sh
fi
./credentials-proxy/run.sh

# Dependency 2: the sandbox image.
if [[ $BUILD -eq 1 ]] || ! container image inspect omp-sandbox >/dev/null 2>&1; then
    ./omp-sandbox/build.sh
fi

exec ./omp-sandbox/run.sh "$@"
