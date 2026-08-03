---
name: git-workflow
description: Branch-per-task, commit as you go, push and PR when done — never commit to main, never amend a commit. Load before any work on the repo.
---

# Git workflow

This is the only way to do repo work. Every task follows the same
flow: worktree, commit as you go, push and PR.

## Use a worktree for isolation

Multiple agents may work on the same repo simultaneously. Creating a
branch with `git switch` mutates the shared working directory — if two
agents do this concurrently, they clobber each other's branch state.
Use a git worktree instead so each task gets its own working directory:

```
git fetch && git worktree add -b <branch> ~/.omp/wt/<branch> origin/main
cd ~/.omp/wt/<branch>
```

`git worktree add` creates a new branch from `origin/main` in a separate
directory. The main checkout is untouched — other agents can work in
parallel without conflict. Work entirely inside the worktree directory.

## Never commit to main

`main` is read-only. All work happens on a feature branch in a worktree
checked out from the latest `main`. Fetch first, then create the worktree
as shown above.

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

## Clean up the worktree

After the PR is merged or closed, remove the worktree:

```
cd <anywhere else> && git worktree remove ~/.omp/wt/<branch>
```

`omp worktree list` shows all agent-managed worktrees; `omp worktree clear`
reclaims orphaned ones.

## Summary

1. `git fetch && git worktree add -b <branch> ~/.omp/wt/<branch> origin/main` — before any work
2. `cd ~/.omp/wt/<branch>` — work inside the worktree
3. `git add` / `git commit` — as you go, not once at the end
4. `git push` + `gh pr create` — when done
5. `git worktree remove ~/.omp/wt/<branch>` — after merge
6. Never `git commit` on `main`. Never `git commit --amend`.
