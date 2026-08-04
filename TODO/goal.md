# TODO
## OpenRouter Advisor Extension for OMP

### Goal

Wire up the OpenRouter `openrouter:advisor` server tool as an OMP extension so the agent can consult a stronger model mid-generation when stuck — pull-based, zero cost on trivial turns.

### Background

- **OpenRouter advisor docs:** https://openrouter.ai/docs/guides/features/server-tools/advisor
- **Prior art (Hermes):** https://github.com/paulcdejean/lightning/tree/main/01_agent/plugins/openrouter-server-tools
- The Hermes plugin used a 2-part pattern:
  1. `register_tool()` — advertises each server tool to the model with a no-op stub handler
  2. `llm_request` middleware — injects the real `{type: "openrouter:advisor", parameters: {...}}` declaration into the outgoing API request's `tools` array
- OpenRouter intercepts the tool call server-side and executes it; the model sees the advice inline as a tool result
