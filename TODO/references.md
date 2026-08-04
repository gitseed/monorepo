# TODO
## OpenRouter Advisor Extension for OMP

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
