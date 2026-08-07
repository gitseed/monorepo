---
name: git-workflow
description: Branch-per-task, commit as you go, push and PR when done — never commit to main, never amend, never force push. Load before any work on the repo.
---

# Git workflow

## Load this skill before any code change

This skill MUST be loaded before you write, edit, delete, or move any
file in the repo. If you are about to change code and have not loaded this
skill, stop and load it first.

The full workflow is: branch → make changes → commit → push → open PR.
These steps are not optional and do not require user confirmation. Never
ask "ready to commit?" — the user asked for a change, so you make the
change and you ship it.

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
2. `git worktree remove ~/.omp/wt/<branch>` — then checkout locally to test
3. `gh pr create --base main --title "<title>" --body "<description>"`

`omp worktree list` shows all agent-managed worktrees; `omp worktree clear`
reclaims orphaned ones.
