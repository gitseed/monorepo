---
name: git-workflow
description: Branch-per-task, commit as you go, push and PR when done — never commit to main, never amend, never force push. Load before any work on the repo.
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

## Never force push

`git push --force` rewrites shared history. It discards commits other
people may have based work on and can leave a remote branch pointing
somewhere no one expects. If a push is rejected, the remote has commits
you don't — fetch and merge them in as a new commit instead of
overwriting. If you need to discard local commits, do it locally; never
overwrite the remote branch.

## Merge instead of rebase

Rebasing rewrites history — the same problem as amending. When you need
to incorporate changes from `main` (or any branch) into your feature
branch, merge them:

```
git fetch && git merge origin/main
```

A merge commit preserves the truth of what happened and when. A rebase
replays your commits on top of the new base and rewrites their hashes,
which is exactly the kind of history rewriting the rest of this skill
forbids.

## Commit as you go

Commit frequently — each logical unit of work gets its own commit.
The frequency is your call, but a single PR should never be one giant
commit unless the change is genuinely atomic.

## Push and open a PR when done

When the work is complete and verified:

1. `git push -u origin <branch>`
2. `gh pr create --base main --title "<title>" --body "<description>"`
3. The PR body should describe what changed and why.

## Release the worktree after opening the PR

Once the PR is open, release the worktree so a human can check out the
branch locally:

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
5. `git worktree remove ~/.omp/wt/<branch>` — after the PR is open, so a human can check out locally
6. Never `git commit` on `main`. Never `git commit --amend`. Never `git push --force`.
7. Merge instead of rebase.
