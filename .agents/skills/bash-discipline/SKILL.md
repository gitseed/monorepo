---
name: bash-discipline
description: Bash script rules — main() wrapper so live edits can't corrupt running scripts, strict mode, quoting, arrays for commands, syntax-check before shipping. Load before writing or editing any .bash/.sh file.
---

# Bash discipline

## Wrap the body in main()

Bash reads scripts lazily, by byte offset. Editing a file while a
prior invocation is still running (a blocking command, a long docker
run) makes the old shell resume at a stale offset in the new bytes —
a bogus "syntax error near unexpected token" at some unrelated line.
Put the entire body in `main() { ... }` with `main "$@"` as the last
line: the whole file parses before anything runs, so in-place edits
are harmless.

## Strict mode, first line after the shebang

`set -euo pipefail`. If one command is allowed to fail, say so at
that command (`|| true`), never by weakening the whole script.

## Quote everything; arrays for built-up commands

Every expansion is quoted: `"$var"`, `"$(cmd)"`, `"$@"`. A command
assembled in a variable becomes an array, expanded as `"${cmd[@]}"` —
never an unquoted string splat, never `eval`.

## Capture $? immediately

In a trap or after a command you must inspect, `local status=$?` on
the very next line. Anything in between clobbers it.

## Prefer [[ ]] and $( )

`[[ ]]` over `[ ]`, `$( )` over backticks. Target bash 3.2 (macOS
`/bin/bash`): no associative arrays, no `${var,,}`, no `mapfile`.

## Verify before shipping

Run `bash -n script.bash` after every edit; run shellcheck if
available. A script that was never syntax-checked is not done.
