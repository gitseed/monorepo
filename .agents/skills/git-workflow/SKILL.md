---
name: git-workflow
description: Load before any work on the repo. Branch-per-task, commit, push, and PR without asking. Never commit to main, never amend, never force push.
---

# Git workflow

Worktrees, commit as you go, push and PR.

## Worktree

Use a worktree — not `git switch` — so concurrent agents don't clobber
each other's branch state:

```
git fetch && git worktree add -b <branch> ~/.omp/wt/<branch> origin/main
cd ~/.omp/wt/<branch>
```

If you are already on the branch you intend to work on (e.g. the user
checked it out), you may work directly in the current working tree
instead of creating a new worktree. New branches you create should still
use a worktree.

## Rules

- **Never commit to main.** All work happens on a feature branch.
- **Never amend.** Add a new commit to correct a wrong one.
- **Never force push.** If rejected, fetch and merge instead.
- **Merge, don't rebase.** Rebasing rewrites history.
- **Commit as you go.** One logical unit per commit.

## When a PR is ready

1. `git push -u origin <branch>`
2. `gh pr create --base main --title "<title>" --body "<description>"`
3. Link the PR URL in your response (e.g. `https://github.com/<owner>/<repo>/pull/<number>`)
4. `git worktree remove ~/.omp/wt/<branch>` — then checkout locally to test if needed (skip if you worked directly in the current working tree)

`omp worktree list` shows all agent-managed worktrees; `omp worktree clear`
reclaims orphaned ones.
