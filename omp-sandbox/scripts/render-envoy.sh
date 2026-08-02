#!/bin/bash
# Render container/envoy.yaml from container/envoy.pkl (the source of
# truth). --check re-renders and diffs instead of writing; up.sh runs
# that before every proxy build so a stale or hand-edited envoy.yaml
# can never reach an image. Rendering happens HERE, on the host, never
# in the containerfile: the proxy image's supply chain stays
# envoy-plus-ca-certificates, with no pkl toolchain inside.
set -euo pipefail

cd "$(dirname -- "$0")/.."

if ! command -v pkl >/dev/null; then
    echo "render-envoy: pkl not found -- install it (brew install pkl)" >&2
    exit 1
fi

render() {
    printf '# GENERATED FILE -- edit container/envoy.pkl, then run scripts/render-envoy.sh\n'
    pkl eval --format yaml container/envoy.pkl
}

if [[ "${1:-}" == "--check" ]]; then
    if ! diff -u container/envoy.yaml <(render); then
        echo "render-envoy: container/envoy.yaml does not match envoy.pkl" >&2
        echo "              (stale render or hand edit); run scripts/render-envoy.sh" >&2
        exit 1
    fi
else
    render > container/envoy.yaml
fi
