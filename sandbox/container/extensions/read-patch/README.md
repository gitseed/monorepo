# Read-Patch Extension

**Temporary.** A monkey patch for [oh-my-pi #7673](https://github.com/can1357/oh-my-pi/issues/7673) — with `memory.backend` off, the built-in `read` tool still advertises `memory://` in its parameter schema, which lures the model into probing a disabled subsystem.

## What it does

- Shadows the built-in `read` tool with an identical tool whose parameter description omits `memory://` (copied verbatim from [upstream PR #7675](https://github.com/can1357/oh-my-pi/pull/7675)).
- Delegates execution to the native `read` via `ctx.invokeTool`, so behavior is unchanged.

## Delete when

Upstream PR #7675 ships. Remove this file and its `COPY` line in `sandbox.containerfile`.

## Known drift

The native `read` description is a runtime-rendered template; this copy is rendered for this sandbox's config (edit tool disabled → no hash-line anchors; images decoded inline). If upstream's `read.md` prompt changes, this text goes stale until deleted.
