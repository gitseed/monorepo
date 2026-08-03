---
name: evidence-discipline
description: Prove a diagnosis against ground truth before fixing, make the test harness match reality before trusting its output, and run the cheapest checker on whatever you edited before claiming done. Load before bug fixes, debugging, or explaining any failure.
---

# Evidence discipline

This repo's costliest failure chain: a broken harness fabricated
evidence of a threat, a fix was built for the phantom, and the fix's
correct behavior was read as more breakage. Each rule breaks that
chain at one link.

## Diagnose before fixing

Prove the problem exists as diagnosed before writing any fix — `ps`,
`docker ps`, an actual repro, whatever ground truth the claim has.
When results contradict your model, measure before editing. A phantom
fix costs three cycles: building it, watching it "fail", removing it.

## Match the harness to reality

A wrong-shaped test fabricates evidence — worse than none, because
decisions load on it.

- Signal the actual process of interest; `kill -9` on a wrapper says
  nothing about the child.
- Test interactive flows interactively (pty), never `nohup &` from a
  headless shell — failing headless only proves it needs a TTY.
- Before believing "X is broken": does the harness exercise the
  production path? If not, fix the harness first.
- Don't build a bespoke harness just to test a helper — that's a
  second, unbudgeted project. Test the real path once.

## "Done" includes the checker

Every edited file has a near-free validity check — `bash -n`, `pkl
eval`, the compiler, the linter. Run it before declaring done or
committing; a diff that was never checked is a claim without
evidence. "It renders later in the build" doesn't count: that
validates the image, not the commit.

## Notice when the loop stops converging

The same area churning three cycles in a row means a premise is
wrong, not the code. Stop, discard conclusions drawn this session,
and re-derive from ground truth — or hand the question to a cold
session that isn't carrying the premise.
