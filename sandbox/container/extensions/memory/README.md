# Memory Extension

A persistent, cross-session memory system for the sandboxed OMP agent. Captures everything the agent hears, says, and thinks, and surfaces relevant memories from past sessions when they're useful now.

## What it does

- **Passive capture**: every user message (`heard`), agent reply (`said`), and thinking block (`thought`) is embedded and stored in the `memories` table (pgvector). `remember` explicitly saves.
- **Four tools**: `recollect` (embedding-similarity search across other sessions), `recall` (full text by id), `remember` (explicit save), `suppress` (hide from recollect).
- **Unprompted surfacing**: on each heard/said/thought event, runs four per-kind similarity queries and injects hits as a `<recollected>` block — custom-role messages that capture can never see. Pre-run surfacing for `heard` embeds the prompt before the agent loop starts (~300ms). Each memory surfaces at most once per session (cooldown).
- **Postgres over unix socket only** — no TCP. Reached via Bun's native SQL bindings.

## Files

| File | Purpose |
|------|---------|
| `memory.ts` | Entry point — tools, capture, surfacing, TUI renderers |
| `config.ts` | Config types, defaults, JSON loader |
| `openrouter.ts` | `summarize()` and `embed()` API calls |
| `memory.json` | Runtime config (models, limits, postgres connection, surfacing thresholds) |
| `APPEND_SYSTEM.md` | Model-facing system prompt contract for the memory system |

## Config

`memory.json` (deployed to `/root/.omp/agent/memory.json`; override path with `MEMORY_CONFIG` env var):

- `enabled`: `false` by default — the extension is inert until turned on.
- `postgres`: socket path, port, database, username, max connections.
- `summary`: model, input char cap, max output tokens, timeout.
- `embedding`: model, input char cap, timeout. The embedding dimension (1536) is baked into the schema (`vector(1536)`) — switching models means re-embedding the table.
- `recollect`: default and max result counts.
- `surfacing`: enabled flag, similarity floor/ceiling, per-kind limit.

`OPENROUTER_API_KEY` stays an env var — it's a secret, not config.

## Schema

See `sandbox/memory/init.sql` — one row per memory in the `memories` table. The `embedding` column is `vector(1536)`; the `summary` column backfills asynchronously (NULL until done — failures stay visible, nothing is fabricated).
