---
name: minimal-change
description: Artifact-vs-decision reasoning, in-scope fixes (delete what review points at, don't widen), declarative-over-imperative, record tested-and-rejected paths. Load before migrations, refactors, and any change with an ask boundary.
---

# Minimal change

## Artifact vs. decision

When a mechanism survived from an older era, ask of each piece:
**load-bearing intent, or archaeological residue?**

- Porting a superseded platform's workaround and rationalizing it as
  architecture is the classic failure ("this is why X exists" — the
  honest answer is often just "it was first").
- When unsure, argue the deletion case to the owner in one line
  before building on top of the artifact.

## Fix the noun, not the comment

When review quotes a thing ("the plain-HTTP listener", "this
variable"), they mean the thing — not its comment. Deliver the
deletion/rename/change. Double-check by re-quoting their exact words
against your diff before claiming the fix.

## Stay inside the named scope

An "up" script starts a session; it does not clean up after other
sessions. Reapers, automation, conveniences are scope leaps unless
named in the ask.

- The deliverable for failure paths is a good escape hatch: an exact,
  ready-to-paste manual command — not automation that presumes on
  human judgement calls.

## Declarative over imperative

When an orchestrator can express topology (compose services,
networks, healthchecks, tofu resources), it owns it. Shell/scripts
keep only what cannot be expressed declaratively: secret injection,
staleness policies, invocation ergonomics. Every bespoke script line
describing a service is a future review comment.

## Record tested-and-rejected paths

When a design is evaluated and rejected, write the rejection AND its
evidence into the repo's notes (learnings.md equivalent). Otherwise
the next session repeats the experiment. Folklore without evidence is
undecidable.
