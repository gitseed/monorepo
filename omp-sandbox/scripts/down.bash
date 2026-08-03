#!/bin/bash
# omp-sandbox/scripts/down.bash — tear down the stable memory stack.
#
# up.bash only tears down its own per-session project; this stops the
# long-lived hindsight service that holds the persistent memory volume.
# Pass -v to also wipe the memory volume (irreversible).
set -euo pipefail

GIT_PROJECT_DIR=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$GIT_PROJECT_DIR"

args=()
if [[ "${1:-}" == "-v" ]]; then args+=(--volumes); fi
docker compose -f omp-sandbox/hindsight.compose.yml down "${args[@]}"
