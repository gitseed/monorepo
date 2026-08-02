---
name: evidence-discipline
description: Diagnose against ground truth before fixing, and make the test harness match reality before trusting its output. Load before bug fixes, debugging sessions, and anytime about to "explain" a failure.
---

# Evidence discipline

The two most expensive failures in this repo's history both violated
this skill: a fix was built for a phantom zombie-process threat, and
the fix's correct behavior was then misread as further breakage — all
on evidence a broken harness fabricated.

## Diagnose before fixing

Before writing ANY fix, spend the thirty seconds proving the problem
exists as diagnosed:

- `ps`, `docker ps`, `/proc`, an actual reproduction — whatever the
  ground truth for the claim is.
- A fix for a phantom costs three cycles: building it, watching it
  "fail" (correctly — there was nothing to find), removing it.
- When results contradict the model, measure before editing.

## Harness realism

A wrong-shaped test fabricates evidence, which is worse than no
evidence because every downstream decision loads on it.

- `kill -9` on a wrapper's pid tells you nothing about the wrapped
  process — target the actual process of interest.
- Interactive flows MUST be tested interactively (pty-capable runner,
  not `nohup &` from a headless shell). A script failing headless
  proves only that it needs a TTY.
- Before trusting "X is broken", ask: does this harness exercise the
  production path? If not, fix the harness first.
