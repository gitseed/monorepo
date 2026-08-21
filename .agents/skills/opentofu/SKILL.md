---
name: opentofu
description: Load before running OpenTofu commands. Planning rules, read-only agent credentials, and sensitive state bucket constraints.
---

# OpenTofu

## Rules

- **Always plan with `-lock=false`:**
  ```
  tofu plan -lock=false
  ```
  Never acquire a state lock when planning.
- **Agent credentials are read-only:** Agents only plan and inspect; `tofu apply` is strictly reserved for humans.
- **`tofu-sensitive` buckets cannot be planned:** Layers backed by `tofu-sensitive` state buckets have no agent read access. Do not attempt to plan them; leave them to humans.
