#!/bin/bash
# Screenshot harness: run a command in a fixed-size tmux pane, optionally
# send keys, capture the resolved grid with colors, render it to PNG.
#
#   scripts/screenshot.bash out.png -- ./dsh-tui -replay demo.ndjson
#   SEND='hello::Enter::sleep 3' scripts/screenshot.bash out.png -- ./dsh-tui ...
#
# SEND is '::'-separated tmux send-keys tokens; 'sleep N' waits instead.
# COLS/ROWS override the 100x30 default. WAIT is the settle time (default 2s).
set -euo pipefail

OUT=$1; shift
[[ ${1:-} == -- ]] && shift
COLS=${COLS:-100} ROWS=${ROWS:-30} WAIT=${WAIT:-2}
DIR=$(cd -- "$(dirname -- "$0")/.." && pwd)
SESSION=dsh-tui-shot-$$

tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS" -c "$DIR" "$*; sleep 60"
trap 'tmux kill-session -t "$SESSION" 2>/dev/null || true' EXIT
sleep "$WAIT"

if [[ -n ${SEND:-} ]]; then
    IFS='::' read -ra tokens <<< "$SEND"
    for tok in "${tokens[@]}"; do
        [[ -z $tok ]] && continue
        if [[ $tok == sleep\ * ]]; then
            sleep "${tok#sleep }"
        else
            tmux send-keys -t "$SESSION" "$tok"
        fi
    done
fi

capture=$(mktemp "${TMPDIR:-/tmp}/dsh-tui-capture.XXXXXX")
# freeze ignores SGR 39/49 (default fg/bg); normalize them to full resets
# so the render matches what a real terminal shows.
tmux capture-pane -e -p -t "$SESSION" | perl -pe 's/\e\[39m/\e[0m/g; s/\e\[49m/\e[0m/g' > "$capture"
if command -v freeze >/dev/null; then
    freeze "$capture" -o "$OUT" >/dev/null
else
    "$DIR/.venv/bin/python" "$DIR/scripts/ansi2png.py" "$capture" "$OUT" "$COLS"
fi
rm -f "$capture"
echo "$OUT"
