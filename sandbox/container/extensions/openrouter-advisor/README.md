# OpenRouter Advisor Extension

A suite of mid-generation advisor tools — each JSON file in `advisors/` defines one tool the model can call mid-generation for guidance. Pull-based, zero cost on trivial turns.

## What it does

- Registers one tool per advisor JSON file. Each tool calls a specified model via OpenRouter for strategic guidance.
- The advisor streams its response back; the agent continues its work informed by the advice.
- Fallback models are tried in order if the primary fails.

## Advisors

| File | Tool name | Model | Purpose |
|------|-----------|-------|---------|
| `advisors/openrouter-advisor.json` | `openrouter_advisor` | `qwen/qwen3.8-max` | Strategic guidance before committing to an approach |
| `advisors/consult-fable.json` | `consult_fable` | `~anthropic/claude-fable-latest` | Wisdom in dire situations only |

## Config

- Each JSON file in `advisors/` must set `name` (the tool name) and may override any default field (model, description, instructions, timeout, etc).
- Edit the JSON to change behavior without touching code.
- `OMP_ADVISORS_DISABLED=1` env var disables all advisor tools.
- `OPENROUTER_API_KEY` env var (set by the sandbox proxy).
