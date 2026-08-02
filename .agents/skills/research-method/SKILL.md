---
name: research-method
description: Read platform/tooling docs before probing behavior; probes verify doc claims and explore genuinely undocumented gaps only, never invent constraints. Load before picking any tool/API/config to build on.
---

# Research method

Probing tells you what happens; documentation tells you what's
supported and intended. Designing from probes alone manufactures
constraints that don't exist.

- Read the platform's docs BEFORE writing config or scripts that
  depend on them. Runtime probing exists to verify doc claims and to
  explore genuinely undocumented gaps — label undocumented findings
  as empirical, not canonical.
- Failures observed mid-experiment that contradict docs are the
  signal to re-read, not to keep probing blindly.
- Costed examples from this repo: hand-rolled runtime IP discovery
  for container-to-container traffic while `network_mode:
  service:` sat in the compose networking docs; a `--dns` build flag
  assumed from the classic builder when buildx doesn't expose it;
  daemon-level option conflicts (hostname/add-host with netns
  sharing) discovered by daemon errors, not by reading.
