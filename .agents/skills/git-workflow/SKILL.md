---
name: git-workflow
description: Branch-per-task, commit as you go, push and PR when done — never commit to main, never amend a commit. Load before any work on the repo.
---

# Git workflow

This is the only way to do repo work. Every task follows the same
flow: branch, commit as you go, push and PR.

## Never commit to main

`main` is read-only. All work happens on a feature branch checked out
from the latest `main`. Fetch first, then branch:

```
git fetch && git switch --no-track -c <branch> origin/main
```

`--no-track` avoids setting up tracking until you push.

## Never amend a commit

Amending rewrites history and hides what actually happened. If a
commit is wrong, add a new commit that corrects it. The history is a
log, not a narrative — messy but truthful beats clean but rewritten.

## Commit as you go

Commit frequently — each logical unit of work gets its own commit.
The frequency is your call, but a single PR should never be one giant
commit unless the change is genuinely atomic.

## Push and open a PR when done

When the work is complete and verified:

1. `git push -u origin <branch>`
2. `gh pr create --base main --title "<title>" --body "<description>"`
3. The PR body should describe what changed and why.


## Summary

1. `git fetch && git switch --no-track -c <branch> origin/main` — before any work
2. `git add` / `git commit` — as you go, not once at the end
3. `git push` + `gh pr create` — when done
4. Never `git commit` on `main`. Never `git commit --amend`.
