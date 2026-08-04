---
name: memory-discipline
description: Consult stored context before acting and persist durable lessons the moment they're established, not at session end. Load before starting work in a new session, before any multi-step plan or design decision, and after root-causing a bug or landing a non-trivial change.
---

# Memory discipline

Memory only helps if you consult it before acting and write to it
after learning. Both are skip-by-default failures: not recalling
means repeating a mistake a prior session already paid for; not
retaining means the next session repeats yours.

## Recall at task start

Before reading code or designing an approach, `recall` for context
relevant to the task:

- Project decisions and conventions that constrain the solution.
- User preferences that shape scope or style.
- Past approaches to the same or similar problems — what worked,
  what was rejected and why.

If any memory is relevant, it changes the plan. If nothing comes
back, you've lost seconds, not hours.

## Reflect before committing to an approach

When multiple designs are visible or a decision is load-bearing,
`reflect` for a synthesized view across memories before locking
in. A single `recall` hit can be stale or partial; `reflect` blends
many memories into a coherent answer.

If `reflect` returns memories that contradict each other, treat the
conflict as signal, not noise: surface both to the user before
acting. Never silently pick the more recent one.

## Retain when you learn something durable

Call `retain` at these moments — not at session end (you'll forget
or lose context), but immediately when the fact is established:

- **A decision was made.** What was decided, why, and what was
  rejected. ("Chose OpenRouter over Morph API directly because no
  new API key needed.")
- **A bug was found and root-caused.** The symptom, the root cause,
  and the fix. ("restapi_object drift was server-added fields
  polluting state, not a real diff.")
- **A user preference was stated.** ("Don't hardcode email, use gh
  CLI.")
- **A tool or pattern was tested and rejected.** What was tried, why
  it failed. ("Serena is heavy: MCP server + LSP per language for
  least coverage.")
- **An approach proved itself.** ("Worktree isolation works;
  git switch clobbers concurrent agents.")

These aren't generic illustrations — they're this repo's actual
retained lessons. New retains should match their level of
specificity: who decided, what was rejected, and why.

Before retaining, `recall` the topic first. If a memory already
covers the fact, update it rather than adding a duplicate — two
near-identical memories drift apart and confuse the next `reflect`.

Each item must be self-contained — include who, what, when, and
why. A memory that says "decided to use X" without why is a
scaffolding debt.

## What does not belong in memory

Ephemeral task state ("currently editing file.ts"), transient
progress ("halfway through the refactor"), and anything the repo
or issue tracker already stores. If a single session produces a
burst of retains, something is being stored that belongs in a PR
description, a code comment, or the issue tracker. Memory is for
durable, cross-session knowledge — not a scratchpad.
