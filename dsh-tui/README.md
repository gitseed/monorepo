# dsh-tui

Bubble Tea TUI spike for DeepSeek Harness. Talks NDJSON JSON-RPC 2.0 to the
SDK runtime (`dsh-jsonrpc-agent`) over stdio — the same wire protocol as the
Python SDK, no web UI involved.

## Setup

The runtime ships as a single-file exe inside the `deepseek-harness-runtime-bin`
wheel; no Node on the host:

```sh
uv venv .venv && uv pip install --python .venv/bin/python deepseek-harness-sdk
go build -o dsh-tui .
```

`ResolveRuntime` globs the exe out of `.venv`; `DSH_RUNTIME_BIN` overrides.

## Run

```sh
DEEPSEEK_API_KEY=... ./dsh-tui                       # bundled default composition
DEEPSEEK_API_KEY=$OPENROUTER_API_KEY \
DEEPSEEK_BASE_URL=https://openrouter.ai/api/v1 \
./dsh-tui -cordis minimal.cordis.yml -model qwen/qwen3.8-max
```

Enter sends (mid-turn sends are steering — the runtime's inbox absorbs
them, shown stacked as `(queued)`); newline is shift+enter, via a
one-line emulator mapping. A plain terminal sends shift+enter as enter
and bubbletea v1 speaks no kitty protocol; ESC-prefixed encodings split
across reads unreliably (verified: atomic ESC CR still parsed as esc,
enter). The robust target is a bare LF (0x0a) — byte-identical to
ctrl+j, unambiguous: kitty `map shift+enter send_text all \n`, Ghostty
`keybind = shift+enter=text:\n`, iTerm2 shift+enter -> "send text"
`\n`, tmux `bind -n S-Enter send-keys C-j` (outer terminal must report
S-Enter). alt+enter also inserts a newline where it arrives atomically.
ctrl+r toggles raw
NDJSON logging of subsequent events. Esc (= ctrl+c) interrupts a running
turn on double-press — the composition routes no `session/cancel` (probed:
-32603), so interrupt kills the runtime and relaunches it; the session
continues. Quit with `/quit`, `/exit`, or `exit` — never a control chord.

Every notification is appended to `<session-root>/tui/<session-id>.ndjson`;
`-session <id>` replays that transcript through the renderer into scrollback
before going live, and transcripts double as `-replay` fixtures.
`-probe -prompt '...'` runs one headless turn and dumps the notification
stream (how the protocol below was captured). `-replay file.ndjson` drives
the UI from a captured stream with no runtime or model.

`make test` = vet + table tests (rendering contract) + golden-frame diff
(`scripts/golden.bash`, `UPDATE=1` regenerates). `make setup` installs the
runtime wheel — platform-specific (this checkout: macos-arm64; the
ai-sandbox image builds its own linux one).

## Screenshot harness

`scripts/screenshot.bash out.png -- ./dsh-tui -replay testdata/demo.ndjson`
runs the TUI in a fixed-size tmux pane, captures the resolved grid with
colors, and renders it to PNG (freeze, falling back to
`scripts/ansi2png.py`) — how an agent looks at its own frames. `SEND`
injects keystrokes, `COLS`/`ROWS`/`WAIT` size and settle the pane. Caveat:
freeze ignores SGR 39/49, so the script normalizes them to full resets.

## Styling rules

Committed lines style with inline SGR only, never width-wrapping, so the
scrollback-commit copy semantics hold. lipgloss styles don't nest (an
inner reset kills the outer color for the rest of the line), so assistant
body text stays the terminal's default foreground and styled spans (code,
bold, bullets, headers) are self-contained islands. Consequence of
terminal-side wrapping: long lines break at the exact column, mid-word —
that's the copy-correctness tradeoff, not a bug.

## Rendering: finalization emission

Inline renderer, no alt screen. Streaming text lives in an erasable live
region (pre-wrapped preview + status + input) and is never committed while
in flight; at finalization the logical lines are emitted once into the
normal-screen flow, unwrapped, autowrap on (tea.Println). The terminal
soft-wraps them, so native selection-copy re-joins rows and committed lines
reflow on resize — the design from oh-my-pi#7879, which Bubble Tea's
inline renderer + Println maps onto directly. Verified at a 60-col pty:
committed replies appear in the byte stream as contiguous >200-char
logical lines with zero DECAWM-off writes.

`minimal.cordis.yml` is vendored from dsh's `examples/jsonrpc-agent`; it takes
arbitrary model ids via `DSH_MODEL` against any OpenAI-compatible
`DEEPSEEK_BASE_URL`. The bundled default composition only resolves the
deepseek-official catalog.

## Protocol notes (captured live)

Client → runtime: `initialize` {cwd, provider, model}, `session/prompt`
{sessionId, contentBlocks} → {messageId}, `shutdown`. Session ids are
client-minted.

Runtime → client notifications: `session.status` {sessionId, status:
running|idle} and `session.event` {sessionId, event:{type, seq, time, data}}.
Event types seen in a full turn, in order: `agent/inbox/spliced`, `turn/start`,
`step/start`, `user/message`, `session/title`, `request/header` (full system
prompt + tool schemas), `request/context`, `assistant/chunk` (block-start /
text-delta / block-end / usage / finish), `assistant/message` (complete,
with usage), `step/end`, `turn/end` {reason.kind: completed|error|max-tokens}.
Idle after `turn/end` marks end of turn. Subagents surface as
`subagent.started`/`subagent.finished` with parent/child session ids.

The runtime can also send client-directed requests (id + method); the
jsonrpc-agent composition loads no approval UI so none appear yet — the TUI
logs and rejects them for now.
