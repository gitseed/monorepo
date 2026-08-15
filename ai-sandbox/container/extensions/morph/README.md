# Morph Fast Apply Extension

An OMP `edit` tool backed by [Morph Fast Apply](https://morphcomposer.com) via OpenRouter. The model provides an instruction + a lazy edit snippet (using `// ... existing code ...` markers), and Morph returns the complete merged file.

## What it does

- Replaces the built-in `edit` tool with Morph-v3-fast for merging partial code edits into files.
- No exact line numbers needed — Morph merges the snippet into the existing file content.
- Works for any file type (YAML, Python, TS, etc).
- 82K token context; conservatively capped at 70K bytes per file.

## Config

- `OPENROUTER_API_KEY` env var (set by the sandbox; the credentials proxy injects the real key).
- `MORPH_MODEL` env var — override the default model (`morph/morph-v3-fast`).
