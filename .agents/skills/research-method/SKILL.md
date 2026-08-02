---
name: research-method
description: Read platform docs before probing behavior; probes verify doc claims or explore genuinely undocumented gaps, never establish constraints on their own. Load before picking any tool/API/config to build on.
---

# Research method

Docs say what is supported and intended; a probe only says what
happened once. Designing from probes alone manufactures constraints
that don't exist.

- Read the docs before writing config or scripts that depend on the
  platform. Probe to verify doc claims or to explore genuinely
  undocumented gaps — and label those findings empirical, not
  canonical.
- A mid-experiment failure that contradicts the docs means re-read
  the docs, not probe harder.
- Paid for here: hand-rolled runtime IP discovery while
  `network_mode: service:` sat in the compose docs; a `--dns` build
  flag assumed from the classic builder that buildx never had.
