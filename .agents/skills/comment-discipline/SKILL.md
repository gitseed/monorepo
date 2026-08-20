---
name: comment-discipline
description: Load before editing code. Stories and rationale belong in commit messages and PR bodies, never in code comments.
---

# Comment discipline

Assume a reader proficient in the stack. When in doubt, delete.

- Comments encode invariants, gotchas, and constraints about THIS system that the code doesn't show: cross-component wiring, security constraints, observed failure modes.
- Self-evident lines get zero comments. That includes restating a name in other words ("an apple is an apple") and standard behavior of the tools in use — proficient readers already know both.
- Stories — why X was chosen over Y, what used to be here, migration context — belong in the commit message and PR description. Never in the diff.
