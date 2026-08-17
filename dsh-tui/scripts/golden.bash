#!/bin/bash
# Golden-frame test: replay the demo fixture at a fixed size and diff the
# captured ANSI grid against testdata/golden.ansi. The live region (input +
# status bar) is stripped — cursor blink phase isn't deterministic; the
# committed content above it is the rendering contract. UPDATE=1 rewrites
# the golden file.
set -euo pipefail

DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
GOLDEN=$DIR/testdata/golden.ansi
SESSION=dsh-tui-golden-$$
LIVE_ROWS=3

tmux new-session -d -s "$SESSION" -x 100 -y 40 -c "$DIR" \
    "env DSH_REPLAY_FAST=1 ./dsh-tui -replay testdata/demo.ndjson; sleep 30"
trap 'tmux kill-session -t "$SESSION" 2>/dev/null || true' EXIT
sleep 3

frame=$(tmux capture-pane -e -p -t "$SESSION" | sed -e 's/[[:space:]]*$//' | sed -e :a -e '/^$/{$d;N;ba' -e '}')
frame=$(printf '%s\n' "$frame" | sed -e "$(( $(printf '%s\n' "$frame" | wc -l) - LIVE_ROWS + 1 )),\$d")

if [[ -n ${UPDATE:-} ]]; then
    printf '%s\n' "$frame" > "$GOLDEN"
    echo "golden updated: $GOLDEN"
    exit 0
fi
if diff <(printf '%s\n' "$frame") "$GOLDEN" > /tmp/dsh-tui-golden.diff; then
    echo "golden frame OK"
else
    echo "golden frame MISMATCH:"
    cat /tmp/dsh-tui-golden.diff | head -40
    exit 1
fi
