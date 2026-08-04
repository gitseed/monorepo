---
name: git-workflow
description: Branch-per-task, commit as you go, push and PR when done — never commit to main, never amend, never force push. Load before any work on the repo.
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

## Rules

- **Never commit to main.** All work happens on a feature branch.
- **Never amend.** Add a new commit to correct a wrong one.
- **Never force push.** If rejected, fetch and merge instead.
- **Merge, don't rebase.** Rebasing rewrites history.
- **Commit as you go.** One logical unit per commit.

## When done

1. `git push -u origin <branch>`
2. `gh pr create --base main --title "<title>" --body "<description>"`
3. After merge: `git worktree remove ~/.omp/wt/<branch>`

`omp worktree list` shows all agent-managed worktrees; `omp worktree clear`
reclaims orphaned ones.
