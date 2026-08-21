---
name: opentofu
description: Run tofu commands. Always plan with lock=false.
---

# OpenTofu

## Planning

Always run plans with `-lock=false`:

```
tofu plan -lock=false
```

Never acquire a state lock when planning. Locks are reserved for applies.
