# dsh-tui — improvement ideas

Notes from a read-through of the spike (`main.go`, `events.go`, `client.go`,
`replay.go`, `runtime.go`, the README, the screenshot harness, and the runtime
binary's surface). Nice state for a spike — the finalization-emission design is
solid and the replay/screenshot loop is a genuinely good dev tool. Roughly in
the order of payoff:

## Interaction completeness (the biggest gaps)

### Esc-to-interrupt
Once a turn is running you can only watch or ctrl+c the whole thing. The
runtime binary contains a `session/cancel` method and `turn/end` already
understands `reason.kind: interrupted` — the SDK jsonrpc server just doesn't
route it yet in this composition, but wiring Esc → cancel (or at least an
abortable `Prompt`) is the single most-missed interaction for an agent TUI.
Even a two-press "Esc once warns, Esc again kills the process" is better than
nothing.

### Approval requests are rejected blind
`reqMsg` auto-answers `-32601` and the README admits this. The moment someone
enables a composition with an approval UI (the binary has `approval/request`,
`approval/asked`, outcome vocabulary `allow/deny/...`), this TUI will silently
break the agent loop. Worth at least rendering the incoming request prominently
and implementing a real allow/deny keybinding against a known method shape,
instead of logging-and-rejecting.

### Double-submit guard
Enter while a turn is running happily fires another `session/prompt`; the
pending-echo and streamBuf will interleave two turns in the live region. Either
queue the input until idle (the runtime has an inbox for exactly this) or
visibly hold it — a one-line `working()` check in the enter handler.

## Session lifecycle

### `-session` resume renders a blank screen
The JSONL history is sitting in `.dsh-sessions/` and the SDK's `Session.run`
shows the load path exists, but resuming gives you nothing but a live region.
Replaying the stored events through the same `summarize()` pipeline on startup
would make resume actually useful — and it's cheap because the renderer is
already a pure notification→lines function.

### Related
Show the `session/title` event in the status bar instead of the truncated
session id (it's currently suppressed in `summarize`), and a `session/list`
picker for choosing what to resume is the natural follow-up. A "dump this
transcript as markdown" command is nearly free given every committed line is
already rendered.

## Rendering fidelity

### The preview is plain text while the commit is styled
Streaming shows raw `**bold**` and `# Header` until finalization flickers it
into styled form — applying `mdInline()` to the live-region preview too would
remove the visible restyle jump.

### Markdown coverage
`mdInline` is a nice island approach, but code fences (``` blocks) are the most
common thing agent replies contain and currently render as literal backticks; a
dim/boxed block spanning fence pairs would help a lot. Blockquotes (`> `),
numbered lists, and italic spans are the other obvious ones. The "styles don't
nest" constraint you documented holds for all of these — they're all
self-terminating islands.

### Streaming tool-call preview
`tool-call-delta` chunks carry `argumentsDelta` and arrive over several
seconds; showing the bash command build up in the live region (the way text
streams) would make long tool generations feel alive instead of dead air
followed by a committed line.

### Tool results are clipped at 2 lines with a byte-count of what was elided
Making the elision count expandable (or at least capping the *shown* lines'
width and showing head+tail for big outputs) would reduce "I wish I could see
that error" moments. Also `toolCallLine` truncates at 120 chars regardless of
terminal width — width-relative would be nicer.

## Status bar telemetry

- The `events` counter is incremented but never displayed — either show it (as
  a debug affordance next to `raw log on`) or drop it.
- `request/context` carries `contextWindow` (1M in the demo); combined with the
  token counts you already track, a context-% bar is the number agent-TUI users
  watch. It's being dropped in `summarize` today.
- Elapsed time for the current turn, and a step/turn counter (`turn/end`
  carries the turn number), are both trivially available and useful.

## Robustness

### Notification backpressure
The `Notifications` channel is capped at 256 and `readLoop` blocks on send when
full, which stalls the pipe reader — a fast stream (e.g. a huge tool output
burst) can deadlock-ish the client until Bubble Tea drains. The idiomatic
Bubble Tea fix is forwarding via `program.Send` or a buffered pump rather than a
listen-cmd per message, or at minimum a much larger buffer plus drop-with-count
behavior.

### Runtime death mid-turn
Leaves the spinner spinning and the pending echo in the live region; `diedMsg`
commits a line but doesn't clear `pending`/`streamBuf` or reset status to
something the glyph logic renders sanely.

### Replay ignores `incomingRequest` lines
`-probe` records them (`{"incomingRequest": ...}` shape), so a capture with
approvals can't exercise the rejection path visually. One extra unmarshal in
`replay.go`.

## Testing & tooling

The screenshot harness is the best asset here and it's only used by hand:

- `summarize()`/`mdInline()`/`textContent()` are pure `Notification → string`
  functions — zero-dependency table tests (including the edge cases: tool-role
  user messages, error chunks, empty text) would protect the rendering
  contract.
- A golden-frame test: run `-replay testdata/demo.ndjson` with
  `DSH_REPLAY_FAST=1` under the screenshot harness at fixed `COLS/ROWS` and
  diff the captured ANSI grid against a committed fixture. Your commit
  messages describe several visual regressions (row tails, joined lines) that
  this would catch mechanically.
- A `make demo-capture` that runs `-probe` against a cheap model and refreshes
  a known-good `testdata/*.ndjson` keeps fixtures from rotting.

## Small cleanups

- `styleText`/`colText` are defined but unused (body text deliberately stays
  default fg) — dead vars.
- `commit()`'s `line == ""` nil guard can't fire; every caller returns
  non-empty.
- `Client.Respond` has no callers (only `RespondError`) until approval UI
  lands.
- The committed binary `dsh-tui/dsh-tui` sits on disk; `.gitignore` covers it
  but a `make build` target (plus a cross-compile note — the vendored runtime
  wheel in this checkout is macos-arm64-only, worth calling out in the README)
  would round out the setup.

## Suggested order

If you want quick wins: Esc-interrupt + the double-submit guard + context-% in
the status bar first (biggest felt improvement, small diffs), then the
golden-frame test so the styling work stays regression-free.
