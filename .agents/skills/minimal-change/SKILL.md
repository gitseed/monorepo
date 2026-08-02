---
name: minimal-change
description: Question inherited mechanisms, change exactly what review names, stay inside the asked scope, prefer declarative topology, record rejected designs with evidence. Load before migrations, refactors, and any change with an ask boundary.
---

# Minimal change

## Artifact vs. decision

For each mechanism inherited from an older era, ask: load-bearing
intent, or residue? "This is why X exists" often means only "X was
first." When unsure, make the one-line deletion case to the owner
before building on top of it.

## Fix the noun, not the comment

When review quotes a thing ("the plain-HTTP listener"), change the
thing — not its comment or docs mention. Before claiming the fix,
re-check their exact words against your diff.

## Stay inside the named scope

Reapers, retries, conveniences — scope leaps unless the ask names
them. For failure paths, deliver an escape hatch (an exact,
ready-to-paste command), not automation that presumes the human's
judgement call.

## Declarative over imperative

If the orchestrator (compose, tofu, ...) can express it, it owns it.
Scripts keep only what can't be declared: secret injection, staleness
policy, invocation ergonomics. Every scripted line describing a
service is a future review comment.

## Record tested-and-rejected paths

Write the rejection and its evidence into the repo's notes, or the
next session repeats the experiment. Folklore without evidence is
undecidable.
