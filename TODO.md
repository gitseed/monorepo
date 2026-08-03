# TODO

## Fix web search

All web search providers are failing:
- Startpage, DuckDuckGo, Ecosia, Google, Mojeek all return errors (bot detection, missing browser daemon, etc.)
- The shared browser daemon (omp.browser.*) isn't running — Ecosia/Google/Mojeek all report "Shared browser daemon unavailable"
- DuckDingle throttles datacenter IPs
- Only Startpage sometimes works but returns no renderable content

### Impact
Cannot do web research from the sandbox. Have to fall back to reading known URLs directly.

### Ideas
- Install and configure a credentialed search provider (Brave, Tavily, Exa, or Kagi API key)
- Fix the browser daemon so Chromium-based providers (Ecosia/Google/Mojeek) work
- Check `hub ps` for `omp.browser.*` daemons and `~/.omp/logs` for details

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

### OMP extension plan

OMP extensions (`pi.registerTool` + `pi.on("before_provider_request")`) map directly to the Hermes pattern:

1. **`pi.registerTool()`** — register a tool named `openrouter:advisor` (or similar) that advertises the advisor to the model. The `execute` handler is a no-op stub — OpenRouter intercepts server-side before OMP ever sees the call.

2. **`pi.on("before_provider_request")`** — inject the real server-tool declaration into the outgoing request's `tools` array:
   ```json
   {
     "type": "openrouter:advisor",
     "parameters": {
       "model": "~anthropic/claude-opus-latest",
       "max_tool_calls": 5
     }
   }
   ```
   This is the `before_provider_request` event from OMP's extension API, which "may replace provider request payload."

### Decisions needed

- [ ] Which advisor model to use (Hermes config used `~anthropic/claude-fable-latest`)
- [ ] Advisor parameters (`max_tool_calls`, `instructions`, `forward_transcript`, `tools` for sub-agent)
- [ ] Just the advisor, or the full server-tool suite (web_search, web_fetch, datetime, fusion, subagent) like the Hermes setup?
- [ ] Where to put the extension file (OMP extensions directory)
- [ ] Whether to make the advisor model configurable at runtime or pin it in the extension

### Reference: OMP extension API

Key surfaces (from `omp://extensions.md`):

- `pi.registerTool({ name, label, description, parameters, execute, ... })` — register a model-callable tool
- `pi.on("before_provider_request", handler)` — fires before each API request; handler may replace the provider request payload (the injection point for server-tool declarations)
- Extension is a TS/JS module exporting a default factory: `export default function(pi) { ... }`

### Reference: Hermes plugin code

- `plugin.yaml` — declares the plugin name/description
- `__init__.py` — `register()` function:
  - `ctx.register_tool(name, toolset, schema, handler, override=True)` for each server tool
  - `ctx.register_middleware("llm_request", inject_server_tools)` appends real declarations to the request's `tools` array

### Reference: OpenRouter advisor parameters

| Field | Default | Description |
|---|---|---|
| `model` | Outer request model | Advisor model (any OpenRouter model) |
| `tools` | None | Tools for the advisor sub-agent (OpenRouter server tools only) |
| `instructions` | None | System instructions for the advisor |
| `forward_transcript` | false | Forward full parent conversation to advisor |
| `max_tool_calls` | Provider default | Max tool-calling steps (1-25) |
| `max_completion_tokens` | Provider default | Max output tokens |
| `reasoning` | Provider default | Reasoning config |
| `temperature` | Provider default | Sampling temperature |

The model invokes the advisor with a `prompt` argument describing what it needs advice on.
