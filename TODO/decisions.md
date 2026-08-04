# TODO
## OpenRouter Advisor Extension for OMP

### Decisions needed

- [ ] Which advisor model to use (Hermes config used `~anthropic/claude-fable-latest`)
- [ ] Advisor parameters (`max_tool_calls`, `instructions`, `forward_transcript`, `tools` for sub-agent)
- [ ] Just the advisor, or the full server-tool suite (web_search, web_fetch, datetime, fusion, subagent) like the Hermes setup?
- [ ] Where to put the extension file (OMP extensions directory)
- [ ] Whether to make the advisor model configurable at runtime or pin it in the extension
