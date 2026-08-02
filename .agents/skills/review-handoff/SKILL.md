---
name: review-handoff
description: Cold self-review before delivery; surface design alternatives as a choice before implementing any; when challenged, run the deciding experiment before defending. Load before presenting work or answering a review challenge.
---

# Review handoff

## Cold adversarial pass (blocking)

Re-read the full diff as the reviewer will. Look for: the thing
they'd flag first; comments scrubbed while their code survived; stale
cross-references; batch-edit typos; changes that do nothing. Minutes
here save a full round-trip per catch.

## Surface alternatives; don't serial-implement

When several designs are visible, present the options with tradeoffs
before building any — one decision cycle instead of N implementation
cycles. In an interactive session, use the option-picker tool (2-5
options, tradeoffs in descriptions, a recommendation) rather than
prose.

## Challenged? Experiment first, rationale after

Treat the challenge as right until the deciding experiment says
otherwise. This thread's tell: a "why current behavior stays" commit
landed minutes before the better design replaced it. Write the
rationale once the evidence exists.

## "Done" contract

1. Run the exact acceptance scenario; quote the output.
2. Map each of the reviewer's quoted asks to the output that
   satisfies it.
3. `git status` clean — nothing unstaged, nothing accidental.
