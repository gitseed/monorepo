# dsh-tui code review — dsh-spike branch

Reviewed: HEAD `f823a6c2`, ~1,900 lines of Go across `cmd/dsh-tui`,
`internal/{harness,render,session,tui}`, plus `plugin/cancel-server.ts`,
scripts, tests, and docs.

## Overall

This is unusually good spike code. The architecture holds up, the
documentation is outstanding, and the "fail loud" culture is actually
enforced in the code rather than just written down. The issues below are
mostly small; nothing structural is wrong.

## What I particularly like

- **The layering is real, not aspirational.** `harness` has zero UI
  imports, `render` is a pure notification→lines function set, `session`
  owns continuity, `tui` is the frontend, `cmd` only wires. The `Conn`
  interface (`internal/harness/harness.go`) is the linchpin — replay
  drives the *exact same* UI with no runtime, which is what makes the
  golden test and screenshot harness possible. That's a genuinely good
  seam.
- **The docs do the job docs should do.** The README's protocol notes are
  captured-live and specific; the comments explain *why* (lipgloss styles
  don't nest, copy-semantics of unwrapped commit, the shift+enter terminal
  research), and CLAUDE.md records invariants "that bit us once already."
  Future maintainers — human or agent — will not have to rediscover any of
  this.
- **The cancel escalation ladder** (plugin → RPC cancel → labeled
  kill+relaunch fallback, degradation announced on stderr at startup) is
  the right shape, and the plugin itself is careful: snapshot-locked
  imports, version-pinned, and the `this.sessions` TS-private-field
  fragility is documented with its failure mode (loud TypeError, not
  silent).
- **Verification tooling as first-class citizen**: `-probe` captures
  fixtures, `-replay` replays them, golden-frame diffs the committed
  region, `scripts/screenshot.bash` renders PNG. That's a real feedback
  loop, not vibes.

## Real issues

### 1. Restarted runtimes leak on exit

`cmd/dsh-tui/main.go:101` defers `Close()` on the *original* client only.
After an interrupt-triggered restart, `restartedMsg`
(`internal/tui/tui.go:210`) swaps `m.client` for the new one, and nothing
ever shuts that one down. `/quit` → `main` returns → the restarted
`dsh-jsonrpc-agent` is orphaned (it only exits on a `shutdown` call).
Either thread a `Close` hook through the model, or have `Run` return the
final conn so main can clean it up. The killed client is also never
`Wait()`ed (`internal/harness/client.go:293`), so it's a zombie until
process exit — cosmetic, but same fix area.

### 2. Queued-prompt previews can vanish early

`internal/tui/tui.go:371-374` pops `m.pending` on *any* `user/message`
event, but tool results also arrive as `user/message` (with
`source.kind == "tool"`). `Summarize` correctly suppresses those from
rendering, but `notified()` pops unconditionally. So when steering prompts
are queued mid-turn, the first tool-result echo dequeues them from the
live region prematurely. Apply the same tool-source filter there before
popping.

### 3. Byte-slicing truncation can split UTF-8 runes

This is a pattern throughout: `internal/session/transcript.go:118`
(`history[len(history)-maxRestore:]`), `internal/render/render.go:53,
103, 210` (`s[:max]+"…"`), `internal/tui/tui.go:511` (`short[:28]`). All
fine while content is ASCII; the first CJK/emoji tool argument or session
title produces a mojibake byte glued to the `…`. Worth one shared
`truncateAtRune` helper in `render`.

### 4. Patched composition written to a fixed name in `$TMPDIR`

`internal/harness/runtime.go:89` via `cmd/dsh-tui/main.go:77`. Two
concurrent dsh-tui instances clobber each other's
`composition-cancel.yml` (a race that only matters at exactly the wrong
moment), and the file is never cleaned up. Use `os.CreateTemp` or name it
per-PID/session.

### 5. Cancel failure with a non-"unknown method" error is a dead end

`internal/tui/tui.go:200-202`: status goes to `"error"`, so `working()`
is false, and a second esc no longer offers an interrupt. It self-heals
when `session.status` flips back, but if the runtime is genuinely wedged
mid-turn the user has no escalation left. Consider keeping the
kill+relaunch path reachable on any cancel failure, not just
unknown-method.

## Nits

- `internal/harness/client.go:105-107` silently skips unparseable JSON
  lines. Probably intentional protocol lenience, but it's the one quiet
  swallow in a codebase that otherwise announces everything — a raw-log
  line or stderr-tail note would match house style.
- `MdInline`'s italic regex (`internal/render/render.go:147`) will
  italicize ` 4 ` in `3 * 4 * 5`. Regex-markdown tax; fine to live with,
  worth knowing.
- `reBold.ReplaceAllStringFunc` + `FindStringSubmatch`
  (`internal/render/render.go:181-183`) re-runs the regex per match.
  Understandable given the replacement needs styling; just flagging it's
  the kind of thing that breaks if two bold spans overlap oddly.
- The live-region width math mixes byte-lengths and cell-widths
  (`internal/tui/tui.go:465`). Harmless for JSON args, but displaywidth
  is already a dependency.

## Test gaps

The render table tests + golden frame cover the rendering contract well.
Nothing covers:

- **`RestoreContext`** — the truncation, tool-role filtering, and
  `<session-restore>` framing are all pure and easily testable, and it's
  the function that guards against the amnesia incident, so it arguably
  deserves the most tests in the repo.
- **Transcript append/read round-trip.**
- **`Client.dispatch`'s three-way message-shape split** — a small test
  with a fake pipe would repay it.

The `tui` model itself is hard to test and, for a spike, leaving it to
the pty/replay harness is a fair call.

## Verification caveat

This review is a **static read only** — the review environment has no Go
toolchain, so `make test`, the golden frame, and a replay were not run.
Per the project's own rules: treat everything above as code-reading, not
probed behavior.

## Recommendation

Merge as a spike. Fix **#1** and **#2** before it carries real usage, and
write the `RestoreContext` tests before the next time anyone touches the
continuity path.
