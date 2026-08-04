# TODO
## OpenRouter Advisor Extension for OMP

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
