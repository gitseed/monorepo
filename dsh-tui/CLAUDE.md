# dsh-tui — working agreements

Layout: `cmd/dsh-tui` wires; `internal/harness` speaks the runtime protocol
(no UI imports); `internal/render` is pure notification→styled-lines;
`internal/session` owns conversation continuity; `internal/tui` is the
Bubble Tea frontend. New code goes in the package that owns the concern —
if no package owns it, that's a design conversation, not a shove.

Invariants that bit us once already — read the package docs before touching:
- The runtime routes only initialize/session-prompt/shutdown. No cancel, no
  session loading. A restarted runtime remembers nothing; internal/session
  is the only memory (see the amnesia incident).
- Committed lines are logical lines: inline SGR styling only, never
  width-wrapping, self-contained style islands. The golden-frame test and
  render tests pin this — run `make test` before every commit.

Practices:
- Fail loud. No `if err != nil { return }` no-ops; a degraded feature says
  so in the UI or refuses to start. `_ =` needs a comment saying why.
- Edit source with editor tools producing reviewable diffs. Never patch Go
  via python/sed string surgery. `gofmt -r` (one rule per invocation) is
  the sanctioned mechanical-rename tool.
- One claim per commit, and say in the message exactly what was verified
  and how ("probed live", "golden green", "pty smoke test"). Stateful
  features need semantic verification: "accepts prompts" is not "remembers".
- Verification tooling: `make test`; `scripts/screenshot.bash` renders real
  frames to PNG; `-replay testdata/*.ndjson` drives the UI deterministically;
  `-probe` captures new fixtures.
- tmux/processes: tear down only resources you created, by your own names
  (`dsh-tui-shot-$$`); inspect and destroy in separate commands.
