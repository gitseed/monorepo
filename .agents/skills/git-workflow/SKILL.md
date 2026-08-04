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
git fetch && git worktree add -b <branch> ~/.pi/wt/<branch> origin/main
cd ~/.pi/wt/<branch>
```

## Rules

- **Never commit to main.** All work happens on a feature branch.
- **Never amend.** Add a new commit to correct a wrong one.
- **Never force push.** If rejected, fetch and merge instead.
- **Merge, don't rebase.** Rebasing rewrites history.
- **Commit as you go.** One logical unit per commit.

## When done

1. `git push -u origin <branch>`
2. `git worktree remove ~/.pi/wt/<branch>` — then checkout locally to test
3. `gh pr create --base main --title "<title>" --body "<description>"`

`git worktree list` shows all worktrees; `git worktree prune` reclaims
orphaned ones.
