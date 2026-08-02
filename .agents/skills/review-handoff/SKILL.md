---
name: review-handoff
description: Cold adversarial self-review before every delivery; alternatives-as-proposals instead of serial implementations; experiment-before-defense when challenged. Load before presenting work for review or answering a review challenge.
---

# Review handoff

## Cold adversarial pass (blocking)

Before delivering, re-read your own full diff as the reviewer will.
Standing questions:

- What would the reviewer flag first?
- Any comment scrubbed while the code it describes survived?
- Stale cross-references (script names, paths, mechanisms removed)?
- Mangled prose from batch edits (missing spaces, wrong subjects)?
- Anything committed that does nothing?

One pass of this self-review costs minutes; a reviewer flagging the
same thing costs a full round-trip.

## Propose alternatives, don't serial-implement

When multiple designs are visible, one message laying out options and
tradeoffs BEFORE building any converts N implementation cycles into
one decision cycle. Reviewers keep you in scope only if they see the
plan before the code.

## Challenged? Experiment first, rationale after

Assume the challenge is right until the deciding experiment says
otherwise. The thread's tell: a commit documenting "why current
behavior stays" landed minutes before the better design replaced it. Write
down the rationale once the evidence has one.

## Verification contract

Before saying "done":

1. Run the exact acceptance scenario, quote relevant output.
2. State explicitly which of the user's quoted phrases each output
   addresses.
3. `git status` clean; no accidental staging, no unintended content.
