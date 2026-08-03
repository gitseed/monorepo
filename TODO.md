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


