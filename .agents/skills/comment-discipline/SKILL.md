---
name: comment-discipline
description: Load before editing code. Stories and rationale belong in commit messages and PR bodies, never in code comments.
---

# Comment discipline

- Comments encode invariants, gotchas, and constraints that are NOT derivable from the code itself.
- Stories — why X was chosen over Y, what used to be here, migration context — belong in the commit message and PR description. Never in the diff.
- Self-evident lines get zero comments. If deleting a comment loses nothing the code doesn't already say, delete it.
