---
name: extension-typecheck
description: Typecheck OMP sandbox extensions before committing — run tsc --noEmit in sandbox/container/extensions after any .ts change. Load before editing or creating extension files.
---

# Extension typecheck discipline

The `sandbox/container/extensions/` directory contains TypeScript files
(OMP extensions) that are never compiled or typechecked by the runtime —
Bun erases `import type` and loads them directly. A wrong import or bad
type silently becomes dead code that ships unnoticed.

## When to typecheck

Run `bun run typecheck` (which executes `tsc --noEmit`) from
`sandbox/container/extensions/` **before committing** any change to a
`.ts` file in that directory. This includes new files, edits, and branch
switches that might introduce type errors.

## How to typecheck

```bash
cd sandbox/container/extensions
bun install          # first time or after dependency changes
bun run typecheck    # tsc --noEmit
```

`bun install` is needed only when `node_modules/` is absent or
`package.json` has changed. `bun run typecheck` is the gate: it must exit
zero before you commit.

## What the typecheck catches

- **Wrong package imports** — `@earendel-works/pi-coding-agent` doesn't
  exist; `@oh-my-pi/pi-coding-agent` is the real package. tsc catches
  this with `TS2307: Cannot find module`.
- **Missing exports** — calling an API that doesn't exist on the
  `ExtensionAPI` interface (e.g. `pi.setLabel` with the wrong signature).
- **Type mismatches** — params, return types, event payloads.

## No CI backstop

There is no GitHub Actions CI for this repo. The typecheck is a local
discipline enforced by this skill, not an automated gate. Skipping it
means bugs ship silently.
