---
name: engineering-craft
description: Review-hardened engineering method — read docs before probing, distinguish artifacts from decisions, fix the noun not the comment, stay inside the named scope. Load for refactors, migrations, infra changes, and any work headed for human review.
---

# Engineering craft (learned from a 32-cycle review thread)

Distilled from a migration (apple/container → OrbStack/docker compose)
that took 32 rounds of human feedback between initial delivery and
merge. Every rule below consumed at least one review cycle. Apply them
BEFORE delivery, not after.

## 1. Docs before probes

Probing tells you what happens; documentation tells you what's
supported and intended. Designing from probes alone manufactures
constraints that don't exist.

- Read the platform/tooling docs BEFORE writing config or scripts.
  Probing exists to verify doc claims and to explore genuinely
  undocumented gaps.
- Examples of cycles this costs: hand-rolled runtime IP discovery
  while `network_mode: service:` sat in the networking docs;
  `docker build --dns` assumed from the classic-builder flag that
  buildx doesn't expose.

## 2. Artifact vs. decision

When a codebase carries a mechanism from an older era, ask of each
piece: **load-bearing intent, or archaeological residue?**

- Porting a workaround from a superseded platform and then
  rationalizing it as architecture is the classic failure ("this is
  why X exists" — usually no other reason than it was first).
- Default question when unsure: make the deletion case to the owner,
  in one line, before building on top of the artifact.

## 3. Fix the noun, not the comment

When review quotes a thing ("the plain HTTP listener"), they mean the
thing — not its comment, not its docs mention. Deliver the deletion.
Double-check by re-quoting their words before you claim the fix.

## 4. Stay inside the named scope

An "up" script starts one session. Reapers, health automation, retries,
project-wide conveniences — all scope leaps unless named in the ask.

- Cleanup-after-catastrophe belongs to the human; the deliverable is
  a good escape hatch (exact manual command in the failure message),
  not automation that presumes judgement.

## 5. Declarative over imperative

When an orchestrator (compose, helm, tofu, ...) can express topology,
it owns it; shell keeps only what it can't express (secret injection,
staleness policies, invocation ergonomics). Every line of bespoke
bash describing services is a future review comment.

## 6. Collateral hygiene — cheap, non-negotiable

Each of these consumed a whole review cycle:

- No unescaped backticks in double-quoted shell strings (commit
  messages get command-substituted; use heredoc `-F -` form).
- Always stage explicitly before commit; verify `git status` clean
  after.
- Re-read YOUR OWN comments after batch edits; batch = typo risk
  (missing spaces, mangled subjects, stale cross-references).
- No verification theater: test the real path once. A harness built
  to test a helper is a second project you didn't budget for.

## 7. Record tested-and-rejected paths

When a simpler design gets evaluated and rejected, write the rejection
AND its evidence into the repo's learnings/notes. Otherwise the next
session (or model) repeats the experiment. Folklore without evidence
is undecidable.

## Verification contract for review-heavy work

Before saying "done": run the exact acceptance command, quote the
output, and state explicitly which of the user's quoted phrases the
output addresses. If you can't point at it, it's not done.
